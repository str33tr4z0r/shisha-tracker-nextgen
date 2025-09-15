package pocketbase

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/shisha-tracker/backend/storage"
)

// Client is a minimal HTTP client for PocketBase-compatible REST endpoints.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	AuthToken  string
}

// NewClient creates a new PocketBase client.
func NewClient(baseURL string) *Client {
	c := &Client{
		BaseURL: baseURL,
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
	// allow using a static token or admin creds via environment for server-to-server calls
	if tok := os.Getenv("POCKETBASE_TOKEN"); tok != "" {
		c.AuthToken = tok
		log.Printf("PocketBase: using token from POCKETBASE_TOKEN")
		return c
	}
	// try admin credentials
	adminEmail := os.Getenv("POCKETBASE_ADMIN_EMAIL")
	adminPass := os.Getenv("POCKETBASE_ADMIN_PASSWORD")
	if adminEmail != "" && adminPass != "" {
		if err := c.Authenticate(adminEmail, adminPass); err != nil {
			log.Printf("PocketBase admin auth failed: %v", err)
		} else {
			log.Printf("PocketBase admin authenticated")
		}
	}
	return c
}

func (c *Client) Authenticate(email, password string) error {
	// admin auth: POST /api/admins/auth-with-password
	payload := map[string]string{
		"identity": email,
		"password": password,
	}
	var resp map[string]interface{}
	if err := c.doRequest("POST", "/api/admins/auth-with-password", payload, &resp); err != nil {
		return err
	}
	// token may be at resp["token"] or resp["data"]["token"]
	if t, ok := resp["token"].(string); ok && t != "" {
		c.AuthToken = t
		return nil
	}
	if data, ok := resp["data"].(map[string]interface{}); ok {
		if t2, ok2 := data["token"].(string); ok2 && t2 != "" {
			c.AuthToken = t2
			return nil
		}
	}
	return fmt.Errorf("admin auth: token not found in response")
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
	// attach admin token if available (support both Authorization and X-Admin-Token)
	if c.AuthToken != "" {
		req.Header.Set("Authorization", "Admin "+c.AuthToken)
		req.Header.Set("X-Admin-Token", c.AuthToken)
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

// helper: try to convert arbitrary PB record item into storage.Shisha
func pbItemToShisha(item interface{}) (storage.Shisha, error) {
	var sh storage.Shisha
	// marshal the generic item back to JSON and unmarshal into our DTO
	b, err := json.Marshal(item)
	if err != nil {
		return sh, err
	}
	// PocketBase records often wrap fields under "record" or have top-level keys that match our DTO.
	// Try direct unmarshal first.
	if err := json.Unmarshal(b, &sh); err == nil {
		return sh, nil
	}
	// If direct unmarshal failed, try to decode assuming item has "record" or "data" wrapper.
	var wrapper map[string]interface{}
	if err := json.Unmarshal(b, &wrapper); err != nil {
		return sh, err
	}
	// common wrappers: "record", "data", or nested map with same fields
	for _, key := range []string{"record", "data", "item"} {
		if v, ok := wrapper[key]; ok {
			b2, err := json.Marshal(v)
			if err != nil {
				continue
			}
			if err := json.Unmarshal(b2, &sh); err == nil {
				return sh, nil
			}
		}
	}
	// as a last resort, try to find "name","flavor" keys at top level inside wrapper
	if _, ok := wrapper["name"]; ok {
		// try a forgiving re-marshal
		b3, _ := json.Marshal(wrapper)
		_ = json.Unmarshal(b3, &sh)
		return sh, nil
	}
	return sh, fmt.Errorf("cannot map pocketbase item to storage.Shisha")
}

// ---- Storage interface implementation (PocketBase collection mapping) ----

// ListShishas returns all shishas via PocketBase collection records.
// It calls /api/collections/shishas/records and maps items to []storage.Shisha.
func (c *Client) ListShishas() ([]storage.Shisha, error) {
	var resp map[string]interface{}
	if err := c.doRequest("GET", "/api/collections/shishas/records?perPage=200", nil, &resp); err != nil {
		return nil, err
	}
	itemsRaw, ok := resp["items"]
	if !ok {
		return nil, fmt.Errorf("unexpected pocketbase response: missing items")
	}
	items, ok := itemsRaw.([]interface{})
	if !ok {
		return nil, fmt.Errorf("unexpected pocketbase response: items type")
	}
	var res []storage.Shisha
	for _, it := range items {
		sh, err := pbItemToShisha(it)
		if err != nil {
			// log and skip problematic item
			log.Printf("pbItemToShisha warning: %v", err)
			continue
		}
		res = append(res, sh)
	}
	return res, nil
}

// GetShisha retrieves a single shisha by id from PocketBase.
// Note: PocketBase record IDs are strings; we attempt to use the numeric id as string.
func (c *Client) GetShisha(id uint) (*storage.Shisha, error) {
	// try numeric id as string
	path := "/api/collections/shishas/records/" + strconv.FormatUint(uint64(id), 10)
	var resp interface{}
	if err := c.doRequest("GET", path, nil, &resp); err != nil {
		return nil, err
	}
	sh, err := pbItemToShisha(resp)
	if err != nil {
		return nil, err
	}
	return &sh, nil
}

// CreateShisha creates a shisha record in PocketBase.
func (c *Client) CreateShisha(s *storage.Shisha) (*storage.Shisha, error) {
	// PocketBase expects the record fields as form data or JSON under "data".
	// We send JSON with the fields at top level (PocketBase accepts JSON body).
	payload := map[string]interface{}{
		"data": s,
	}
	var resp interface{}
	if err := c.doRequest("POST", "/api/collections/shishas/records", payload, &resp); err != nil {
		return nil, err
	}
	sh, err := pbItemToShisha(resp)
	if err != nil {
		return nil, err
	}
	return &sh, nil
}

// UpdateShisha updates a record in PocketBase.
func (c *Client) UpdateShisha(id uint, s *storage.Shisha) (*storage.Shisha, error) {
	path := "/api/collections/shishas/records/" + strconv.FormatUint(uint64(id), 10)
	payload := map[string]interface{}{
		"data": s,
	}
	var resp interface{}
	if err := c.doRequest("PATCH", path, payload, &resp); err != nil {
		return nil, err
	}
	sh, err := pbItemToShisha(resp)
	if err != nil {
		return nil, err
	}
	return &sh, nil
}

// DeleteShisha deletes a record in PocketBase.
func (c *Client) DeleteShisha(id uint) error {
	path := "/api/collections/shishas/records/" + strconv.FormatUint(uint64(id), 10)
	return c.doRequest("DELETE", path, nil, nil)
}

// AddRating posts a rating for a shisha.
// This implementation stores ratings as a nested field if present.
func (c *Client) AddRating(id uint, user string, score int) error {
	// Fetch record, append rating to ratings array, PATCH record back.
	sh, err := c.GetShisha(id)
	if err != nil {
		return err
	}
	r := map[string]interface{}{
		"user":  user,
		"score": score,
	}
	// convert existing ratings to []interface{}
	var ratings []interface{}
	for _, rr := range sh.Ratings {
		ratings = append(ratings, rr)
	}
	ratings = append(ratings, r)
	payload := map[string]interface{}{
		"data": map[string]interface{}{
			"ratings": ratings,
		},
	}
	path := "/api/collections/shishas/records/" + strconv.FormatUint(uint64(id), 10)
	return c.doRequest("PATCH", path, payload, nil)
}

// AddComment posts a comment for a shisha.
func (c *Client) AddComment(id uint, user, message string) error {
	sh, err := c.GetShisha(id)
	if err != nil {
		return err
	}
	cm := map[string]interface{}{
		"user":    user,
		"message": message,
	}
	var comments []interface{}
	for _, cc := range sh.Comments {
		comments = append(comments, cc)
	}
	comments = append(comments, cm)
	payload := map[string]interface{}{
		"data": map[string]interface{}{
			"comments": comments,
		},
	}
	path := "/api/collections/shishas/records/" + strconv.FormatUint(uint64(id), 10)
	return c.doRequest("PATCH", path, payload, nil)
}
