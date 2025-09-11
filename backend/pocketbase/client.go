package pocketbase

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/shisha-tracker/backend/storage"
)

// Client is a minimal HTTP client for PocketBase-compatible REST endpoints.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
}

// NewClient creates a new PocketBase client.
func NewClient(baseURL string) *Client {
	return &Client{
		BaseURL: baseURL,
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

func (c *Client) doRequest(method, path string, reqBody interface{}, out interface{}) error {
	var body io.Reader
	if reqBody != nil {
		b, err := json.Marshal(reqBody)
		if err != nil {
			return err
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, c.BaseURL+path, body)
	if err != nil {
		return err
	}
	if reqBody != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("request failed: %s: %s", resp.Status, string(b))
	}
	if out == nil {
		return nil
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// ---- Storage interface implementation ----

// ListShishas returns all shishas via the REST API.
func (c *Client) ListShishas() ([]storage.Shisha, error) {
	var res []storage.Shisha
	if err := c.doRequest("GET", "/api/shishas", nil, &res); err != nil {
		return nil, err
	}
	return res, nil
}

// GetShisha retrieves a single shisha by id.
func (c *Client) GetShisha(id uint) (*storage.Shisha, error) {
	var s storage.Shisha
	if err := c.doRequest("GET", "/api/shishas/"+strconv.FormatUint(uint64(id), 10), nil, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// CreateShisha creates a shisha record.
func (c *Client) CreateShisha(s *storage.Shisha) (*storage.Shisha, error) {
	var out storage.Shisha
	if err := c.doRequest("POST", "/api/shishas", s, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// UpdateShisha updates a shisha by id.
func (c *Client) UpdateShisha(id uint, s *storage.Shisha) (*storage.Shisha, error) {
	var out storage.Shisha
	if err := c.doRequest("PUT", "/api/shishas/"+strconv.FormatUint(uint64(id), 10), s, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

// DeleteShisha deletes a shisha by id.
func (c *Client) DeleteShisha(id uint) error {
	return c.doRequest("DELETE", "/api/shishas/"+strconv.FormatUint(uint64(id), 10), nil, nil)
}

// AddRating posts a rating for a shisha.
func (c *Client) AddRating(id uint, user string, score int) error {
	payload := map[string]interface{}{
		"user":  user,
		"score": score,
	}
	return c.doRequest("POST", "/api/shishas/"+strconv.FormatUint(uint64(id), 10)+"/ratings", payload, nil)
}

// AddComment posts a comment for a shisha.
func (c *Client) AddComment(id uint, user, message string) error {
	payload := map[string]interface{}{
		"user":    user,
		"message": message,
	}
	return c.doRequest("POST", "/api/shishas/"+strconv.FormatUint(uint64(id), 10)+"/comments", payload, nil)
}