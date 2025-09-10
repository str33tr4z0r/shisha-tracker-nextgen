package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type User struct {
	ID   uint   `gorm:"primaryKey" json:"id"`
	Name string `json:"name"`
}

type Manufacturer struct {
	ID   uint   `gorm:"primaryKey" json:"id"`
	Name string `json:"name"`
}

type Shisha struct {
	ID             uint         `gorm:"primaryKey" json:"id"`
	Name           string       `json:"name"`
	Flavor         string       `json:"flavor"`
	ManufacturerID uint         `json:"manufacturer_id"`
	Manufacturer   Manufacturer `json:"manufacturer" gorm:"foreignKey:ManufacturerID"`
	Ratings        []Rating     `json:"ratings" gorm:"constraint:OnDelete:CASCADE;"`
	Comments       []Comment    `json:"comments" gorm:"constraint:OnDelete:CASCADE;"`
}

type Rating struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	ShishaID uint  `json:"shisha_id"`
	User    string `json:"user"`
	Score   int    `json:"score"`
}

type Comment struct {
	ID      uint   `gorm:"primaryKey" json:"id"`
	ShishaID uint  `json:"shisha_id"`
	User    string `json:"user"`
	Message string `json:"message"`
}

var db *gorm.DB

func main() {
	// allow full DATABASE_URL or construct DSN from individual env vars (used by Helm values)
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		host := os.Getenv("DATABASE_HOST")
		if host == "" {
			host = "localhost"
		}
		port := os.Getenv("DATABASE_PORT")
		if port == "" {
			port = "26257"
		}
		user := os.Getenv("DATABASE_USER")
		if user == "" {
			user = "root"
		}
		name := os.Getenv("DATABASE_NAME")
		if name == "" {
			name = "shisha"
		}
		password := os.Getenv("DATABASE_PASSWORD") // optional, may be provided via secret
		// build DSN for lib/pq (Postgres-compatible)
		if password != "" {
			dsn = fmt.Sprintf("host=%s port=%s user=%s dbname=%s password=%s sslmode=disable", host, port, user, name, password)
		} else {
			dsn = fmt.Sprintf("host=%s port=%s user=%s dbname=%s sslmode=disable", host, port, user, name)
		}
	}
	var err error
	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalf("failed to connect database: %v", err)
	}
	
	// Respect SKIP_MIGRATIONS environment variable to allow manual control in Kubernetes
	skip := strings.ToLower(os.Getenv("SKIP_MIGRATIONS"))
	if skip == "true" || skip == "1" || skip == "yes" {
		log.Println("Skipping automatic migrations because SKIP_MIGRATIONS is set")
	} else {
		if err := db.AutoMigrate(&User{}, &Manufacturer{}, &Shisha{}, &Rating{}, &Comment{}); err != nil {
			log.Fatalf("migration failed: %v", err)
		}
	}

	r := gin.Default()
	api := r.Group("/api")
	{
		api.GET("/healthz", healthHandler)
		api.GET("/ready", readyHandler)
		api.GET("/metrics", metricsHandler)
		api.GET("/info", infoHandler)
	
		api.GET("/shishas", listShishas)
		api.POST("/shishas", createShisha)
		api.GET("/shishas/:id", getShisha)
		api.PUT("/shishas/:id", updateShisha)
		api.DELETE("/shishas/:id", deleteShisha)
	
		api.POST("/shishas/:id/ratings", addRating)
		api.POST("/shishas/:id/comments", addComment)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	addr := fmt.Sprintf(":%s", port)
	r.Run(addr)
}

func healthHandler(c *gin.Context) {
	c.Status(http.StatusOK)
}

func readyHandler(c *gin.Context) {
	c.Status(http.StatusOK)
}

func metricsHandler(c *gin.Context) {
	c.String(http.StatusOK, "# shisha mock metrics\nshisha_requests_total 0\n")
}

func infoHandler(c *gin.Context) {
	// prefer POD_NAME (set via Downward API in Kubernetes), fallback to hostname (container id)
	pod := os.Getenv("POD_NAME")
	hostname, _ := os.Hostname()
	if pod == "" {
		pod = hostname
	}

	// Try to read container id from /proc/self/hostname (works in many container runtimes).
	// Fall back to os.Hostname() if reading fails.
	containerID := ""
	if b, err := os.ReadFile("/proc/self/hostname"); err == nil {
		containerID = strings.TrimSpace(string(b))
	}
	if containerID == "" {
		containerID = hostname
	}

	c.JSON(http.StatusOK, gin.H{
		"pod":          pod,
		"hostname":     hostname,
		"container_id": containerID,
	})
}

func listShishas(c *gin.Context) {
	var shishas []Shisha
	if err := db.Preload("Manufacturer").Preload("Ratings").Preload("Comments").Find(&shishas).Error; err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusOK, shishas)
}

func getShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var s Shisha
	if err := db.Preload("Manufacturer").Preload("Ratings").Preload("Comments").First(&s, id).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.JSON(http.StatusOK, s)
}

func createShisha(c *gin.Context) {
	var in Shisha
	if err := c.BindJSON(&in); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}

	// manufacturer handling: find or create by name if provided
	if in.Manufacturer.ID == 0 && in.Manufacturer.Name != "" {
		var m Manufacturer
		if err := db.Where("name = ?", in.Manufacturer.Name).First(&m).Error; err != nil {
			m = Manufacturer{Name: in.Manufacturer.Name}
			db.Create(&m)
		}
		in.ManufacturerID = m.ID
	} else if in.Manufacturer.ID != 0 {
		in.ManufacturerID = in.Manufacturer.ID
	}

	if err := db.Create(&in).Error; err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, in)
}

func updateShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var in Shisha
	if err := c.BindJSON(&in); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var existing Shisha
	if err := db.First(&existing, id).Error; err != nil {
		c.Status(http.StatusNotFound)
		return
	}

	existing.Name = in.Name
	existing.Flavor = in.Flavor

	if in.Manufacturer.ID != 0 || in.Manufacturer.Name != "" {
		var m Manufacturer
		if in.Manufacturer.ID != 0 {
			db.First(&m, in.Manufacturer.ID)
		} else {
			if err := db.Where("name = ?", in.Manufacturer.Name).First(&m).Error; err != nil {
				m = Manufacturer{Name: in.Manufacturer.Name}
				db.Create(&m)
			}
		}
		existing.ManufacturerID = m.ID
	}

	db.Save(&existing)
	c.JSON(http.StatusOK, existing)
}

func deleteShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := db.Delete(&Shisha{}, id).Error; err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	c.Status(http.StatusNoContent)
}

func addRating(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var r Rating
	if err := c.BindJSON(&r); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	r.ShishaID = uint(id)
	if err := db.Create(&r).Error; err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, r)
}

func addComment(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var cm Comment
	if err := c.BindJSON(&cm); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	cm.ShishaID = uint(id)
	if err := db.Create(&cm).Error; err != nil {
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, cm)
}