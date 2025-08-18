package main

import (
	"net/http"
	"sync"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

type Manufacturer struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type Rating struct {
	User      string `json:"user"`
	Score     int    `json:"score"`
	Timestamp int64  `json:"timestamp,omitempty"`
}

type Comment struct {
	User    string `json:"user"`
	Message string `json:"message"`
}

type Shisha struct {
	ID          int          `json:"id"`
	Name        string       `json:"name"`
	Flavor      string       `json:"flavor"`
	Manufacturer Manufacturer `json:"manufacturer"`
	Ratings     []Rating     `json:"ratings"`
	Comments    []Comment    `json:"comments"`
	SmokedCount int          `json:"smokedCount"`
}

var (
	mu     sync.Mutex
	store  = make(map[int]Shisha)
	nextID = 1
)

func main() {
	r := gin.Default()

	api := r.Group("/api")
	{
		api.GET("/healthz", healthHandler)
		api.GET("/ready", readyHandler)
		api.GET("/metrics", metricsHandler)

		api.GET("/shishas", listShishas)
		api.POST("/shishas", createShisha)
		api.GET("/shishas/:id", getShisha)
		api.PUT("/shishas/:id", updateShisha)
		api.DELETE("/shishas/:id", deleteShisha)

		api.POST("/shishas/:id/ratings", addRating)
		api.POST("/shishas/:id/comments", addComment)
		// increment smoked counter (persistent)
		api.POST("/shishas/:id/smoked", addSmoked)
	}

	seedSample()

	r.Run(":8080")
}

func healthHandler(c *gin.Context) {
	c.Status(http.StatusOK)
}

func readyHandler(c *gin.Context) {
	c.Status(http.StatusOK)
}

func metricsHandler(c *gin.Context) {
	c.String(http.StatusOK, "# mock metrics\nshisha_requests_total 42\n")
}

func listShishas(c *gin.Context) {
	mu.Lock()
	defer mu.Unlock()
	res := make([]Shisha, 0, len(store))
	for _, v := range store {
		res = append(res, v)
	}
	c.JSON(http.StatusOK, res)
}

func getShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	mu.Lock()
	s, ok := store[id]
	mu.Unlock()
	if !ok {
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
	mu.Lock()
	in.ID = nextID
	nextID++
	store[in.ID] = in
	mu.Unlock()
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
	mu.Lock()
	_, ok := store[id]
	if !ok {
		mu.Unlock()
		c.Status(http.StatusNotFound)
		return
	}
	in.ID = id
	store[id] = in
	mu.Unlock()
	c.JSON(http.StatusOK, in)
}

func deleteShisha(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	mu.Lock()
	_, ok := store[id]
	if ok {
		delete(store, id)
	}
	mu.Unlock()
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
	// set timestamp server-side
	r.Timestamp = time.Now().Unix()
	mu.Lock()
	s, ok := store[id]
	if !ok {
		mu.Unlock()
		c.Status(http.StatusNotFound)
		return
	}
	s.Ratings = append(s.Ratings, r)
	store[id] = s
	mu.Unlock()
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
	mu.Lock()
	s, ok := store[id]
	if !ok {
		mu.Unlock()
		c.Status(http.StatusNotFound)
		return
	}
	s.Comments = append(s.Comments, cm)
	store[id] = s
	mu.Unlock()
	c.JSON(http.StatusCreated, cm)
}

// addSmoked increments the persistent smoked counter for a shisha
func addSmoked(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.Status(http.StatusBadRequest)
		return
	}
	mu.Lock()
	s, ok := store[id]
	if !ok {
		mu.Unlock()
		c.Status(http.StatusNotFound)
		return
	}
	s.SmokedCount++
	store[id] = s
	mu.Unlock()
	c.JSON(http.StatusOK, gin.H{"smokedCount": s.SmokedCount})
}

func seedSample() {
	mu.Lock()
	store[nextID] = Shisha{
		ID:     nextID,
		Name:   "Mint Breeze",
		Flavor: "Minze",
		Manufacturer: Manufacturer{
			ID:   1,
			Name: "Al Fakher",
		},
		// Bob hatte Geschmack -> mindestens 0.5 Sterne (Score 1)
		Ratings:  []Rating{{User: "alice", Score: 4}, {User: "bob", Score: 1}},
		Comments: []Comment{{User: "bob", Message: "Leicht und frisch"}},
	}
	nextID++
	mu.Unlock()
}