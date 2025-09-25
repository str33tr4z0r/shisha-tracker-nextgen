package storage

import (
	"errors"

	"gorm.io/gorm"
)

// GormAdapter implements Storage backed by GORM DB.
type GormAdapter struct {
	DB *gorm.DB
}

func NewGormAdapter(db *gorm.DB) *GormAdapter {
	return &GormAdapter{DB: db}
}

func (g *GormAdapter) ListShishas() ([]Shisha, error) {
	// local struct mapping
	type Manufacturer struct {
		ID   uint   `json:"id"`
		Name string `json:"name"`
	}
	type Rating struct {
		User  string `json:"user"`
		Score int    `json:"score"`
	}
	type Comment struct {
		User    string `json:"user"`
		Message string `json:"message"`
	}
	type ShishaGorm struct {
		ID           uint
		Name         string
		Flavor       string
		Manufacturer Manufacturer
		Ratings      []Rating
		Comments     []Comment
	}

	var rows []Shisha
	// naive implementation: use raw queries to map to storage.Shisha
	// This keeps adapter simple for now; full mapping omitted for brevity.
	if err := g.DB.Find(&rows).Error; err != nil {
		return nil, err
	}
	return rows, nil
}

func (g *GormAdapter) GetShisha(id uint) (*Shisha, error) {
	var s Shisha
	if err := g.DB.First(&s, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &s, nil
}

func (g *GormAdapter) CreateShisha(s *Shisha) (*Shisha, error) {
	if err := g.DB.Create(s).Error; err != nil {
		return nil, err
	}
	return s, nil
}

func (g *GormAdapter) UpdateShisha(id uint, s *Shisha) (*Shisha, error) {
	var existing Shisha
	if err := g.DB.First(&existing, id).Error; err != nil {
		return nil, err
	}
	s.ID = id
	if err := g.DB.Save(s).Error; err != nil {
		return nil, err
	}
	return s, nil
}

func (g *GormAdapter) DeleteShisha(id uint) error {
	if err := g.DB.Delete(&Shisha{}, id).Error; err != nil {
		return err
	}
	return nil
}

func (g *GormAdapter) AddRating(id uint, user string, score int) error {
	// simple GORM-backed implementation: insert into ratings table
	type ratingGorm struct {
		ID       uint   `gorm:"primaryKey"`
		ShishaID uint   `gorm:"column:shisha_id"`
		User     string `gorm:"column:user"`
		Score    int    `gorm:"column:score"`
	}
	r := ratingGorm{
		ShishaID: id,
		User:     user,
		Score:    score,
	}
	if err := g.DB.Create(&r).Error; err != nil {
		return err
	}
	return nil
}

func (g *GormAdapter) AddComment(id uint, user, message string) error {
	// simple GORM-backed implementation: insert into comments table
	type commentGorm struct {
		ID       uint   `gorm:"primaryKey"`
		ShishaID uint   `gorm:"column:shisha_id"`
		User     string `gorm:"column:user"`
		Message  string `gorm:"column:message"`
	}
	c := commentGorm{
		ShishaID: id,
		User:     user,
		Message:  message,
	}
	if err := g.DB.Create(&c).Error; err != nil {
		return err
	}
	return nil
}

func (g *GormAdapter) AddSmoked(id uint) error {
	// increment smoked counter atomically
	if err := g.DB.Model(&Shisha{}).Where("id = ?", id).UpdateColumn("smoked", gorm.Expr("COALESCE(smoked,0) + ?", 1)).Error; err != nil {
		return err
	}
	return nil
}
