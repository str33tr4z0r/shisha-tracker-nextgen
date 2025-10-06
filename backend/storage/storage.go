package storage

// Manufacturer represents a shisha manufacturer.
type Manufacturer struct {
	ID   uint   `json:"id"`
	Name string `json:"name"`
}

// Rating represents a user rating for a shisha.
type Rating struct {
	User      string `json:"user"`
	Score     int    `json:"score"`
	Timestamp int64  `json:"timestamp,omitempty"`
}

// Comment represents a user comment for a shisha.
type Comment struct {
	User    string `json:"user"`
	Message string `json:"message"`
}

// Shisha minimal DTO for storage layer
type Shisha struct {
	ID           uint         `json:"id"`
	Name         string       `json:"name"`
	Flavor       string       `json:"flavor"`
	Manufacturer Manufacturer `json:"manufacturer"`
	Smoked       int          `json:"smoked,omitempty"`
	Ratings      []Rating     `json:"ratings,omitempty"`
	Comments     []Comment    `json:"comments,omitempty"`
}

// DBInfo represents basic information about the configured database/backend.
type DBInfo struct {
	IsCluster bool `json:"isCluster"`
	Nodes     int  `json:"nodes,omitempty"`
}

// Storage interface abstracts data operations used by the server handlers.
type Storage interface {
	ListShishas() ([]Shisha, error)
	GetShisha(id uint) (*Shisha, error)
	CreateShisha(s *Shisha) (*Shisha, error)
	UpdateShisha(id uint, s *Shisha) (*Shisha, error)
	DeleteShisha(id uint) error
	AddRating(id uint, user string, score int) error
	AddComment(id uint, user, message string) error
	// Increment smoked counter for shisha with given id.
	AddSmoked(id uint) error
	// Health checks connectivity to the underlying storage (e.g. DB or CouchDB cluster).
	Health() error
	// DBInfo returns information about the storage backend (cluster membership, node count, ...).
	DBInfo() (*DBInfo, error)
}
