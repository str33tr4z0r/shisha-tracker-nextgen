package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/shisha-tracker/backend/storage"
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
	ID       uint   `gorm:"primaryKey" json:"id"`
	ShishaID uint   `json:"shisha_id"`
	User     string `json:"user"`
	Score    int    `json:"score"`
}

type Comment struct {
	ID       uint   `gorm:"primaryKey" json:"id"`
	ShishaID uint   `json:"shisha_id"`
	User     string `json:"user"`
	Message  string `json:"message"`
}

var db *gorm.DB
var storageEngine storage.Storage

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
	// choose storage backend: default CouchDB ("couchdb") or GORM (legacy)
	storageMode := os.Getenv("STORAGE")
	if storageMode == "" {
		storageMode = "couchdb"
	}

	if storageMode == "couchdb" {
		couchURL := os.Getenv("COUCHDB_URL")
		couchUser := os.Getenv("COUCHDB_USER")
		couchPass := os.Getenv("COUCHDB_PASSWORD")
		couchDB := os.Getenv("COUCHDB_DB")
		adapter, err := storage.NewCouchAdapter(couchURL, couchUser, couchPass, couchDB)
		if err != nil {
			log.Fatalf("failed to initialize CouchDB adapter: %v", err)
		}
		storageEngine = adapter
		log.Printf("Using CouchDB storage backend (%s/%s)", couchURL, couchDB)
	} else {
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
		if err != nil {
			log.Fatalf("failed to connect database: %v", err)
		}
		storageEngine = storage.NewGormAdapter(db)
		log.Println("Using GORM storage backend")
	}

	// Automatic DB migrations removed (CouchDB as storage; manage migrations externally if needed).
	log.Println("Automatic DB migrations disabled (CouchDB assumed)")

	r := gin.Default()
	api := r.Group("/api")
	{
		api.GET("/healthz", healthHandler)
		api.GET("/ready", readyHandler)
		api.GET("/metrics", metricsHandler)
		api.GET("/info", infoHandler)
		api.GET("/container-id", containerIDHandler)

		api.GET("/shishas", listShishas)
		api.POST("/shishas", createShisha)
		api.GET("/shishas/:id", getShisha)
		api.PUT("/shishas/:id", updateShisha)
		api.DELETE("/shishas/:id", deleteShisha)

		api.POST("/shishas/:id/ratings", addRating)
		api.POST("/shishas/:id/comments", addComment)
		api.POST("/shishas/:id/smoked", addSmoked)
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

func containerIDHandler(c *gin.Context) {
	// Return only the container identifier (useful for the frontend)
	containerID := ""
	if b, err := os.ReadFile("/proc/self/hostname"); err == nil {
		containerID = strings.TrimSpace(string(b))
	}
	if containerID == "" {
		hostname, _ := os.Hostname()
		containerID = hostname
	}
	c.JSON(http.StatusOK, gin.H{"container_id": containerID})
}

func listShishas(c *gin.Context) {
	log.Printf("GET /api/shishas start remote=%s", c.ClientIP())
	shishas, err := storageEngine.ListShishas()
	if err != nil {
		log.Printf("GET /api/shishas storage error: %v", err)
		c.Status(http.StatusInternalServerError)
		return
	}
	if shishas == nil {
		log.Printf("GET /api/shishas: storage returned nil slice - normalizing to empty")
		shishas = make([]storage.Shisha, 0)
	}
	log.Printf("GET /api/shishas ok count=%d", len(shishas))
	c.JSON(http.StatusOK, shishas)
}

func getShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	s, err := storageEngine.GetShisha(uint(id))
	if err != nil {
		log.Printf("storage.GetShisha id=%d error: %v", id, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	if s == nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.JSON(http.StatusOK, s)
}

func createShisha(c *gin.Context) {
	var in storage.Shisha
	if err := c.BindJSON(&in); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}

	out, err := storageEngine.CreateShisha(&in)
	if err != nil {
		log.Printf("storage.CreateShisha input=%+v error: %v", in, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, out)
}

func updateShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var in storage.Shisha
	if err := c.BindJSON(&in); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	out, err := storageEngine.UpdateShisha(uint(id), &in)
	if err != nil {
		log.Printf("storage.UpdateShisha id=%d input=%+v error: %v", id, in, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusOK, out)
}

func deleteShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := storageEngine.DeleteShisha(uint(id)); err != nil {
		log.Printf("storage.DeleteShisha id=%d error: %v", id, err)
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
	var req struct {
		User  string `json:"user"`
		Score int    `json:"score"`
	}
	if err := c.BindJSON(&req); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := storageEngine.AddRating(uint(id), req.User, req.Score); err != nil {
		log.Printf("storage.AddRating id=%d user=%s score=%d error: %v", id, req.User, req.Score, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"user": req.User, "score": req.Score})
}

func addComment(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	var req struct {
		User    string `json:"user"`
		Message string `json:"message"`
	}
	if err := c.BindJSON(&req); err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := storageEngine.AddComment(uint(id), req.User, req.Message); err != nil {
		log.Printf("storage.AddComment id=%d user=%s error: %v", id, req.User, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	c.JSON(http.StatusCreated, gin.H{"user": req.User, "message": req.Message})
}

func addSmoked(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	if err := storageEngine.AddSmoked(uint(id)); err != nil {
		log.Printf("storage.AddSmoked id=%d error: %v", id, err)
		c.Status(http.StatusInternalServerError)
		return
	}

	// fetch updated shisha and return smoked count to the client
	s, err := storageEngine.GetShisha(uint(id))
	if err != nil {
		log.Printf("storage.GetShisha id=%d error: %v", id, err)
		c.Status(http.StatusInternalServerError)
		return
	}
	if s == nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.JSON(http.StatusOK, gin.H{"smokedCount": s.Smoked})
}
