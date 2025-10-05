package storage

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// CouchAdapter implements Storage backed by CouchDB HTTP API.
type CouchAdapter struct {
	client  *http.Client
	baseURL string
	dbName  string
	user    string
	pass    string
}

// NewCouchAdapter creates adapter and ensures database exists.
func NewCouchAdapter(baseURL, user, pass, dbName string) (*CouchAdapter, error) {
	if baseURL == "" {
		baseURL = os.Getenv("COUCHDB_URL")
	}
	// sensible local default when env not set
	if baseURL == "" {
		baseURL = "http://localhost:5984"
	}
	if user == "" {
		user = os.Getenv("COUCHDB_USER")
	}
	if pass == "" {
		pass = os.Getenv("COUCHDB_PASSWORD")
	}
	if dbName == "" {
		dbName = os.Getenv("COUCHDB_DB")
		if dbName == "" {
			dbName = "shisha"
		}
	}
	c := &CouchAdapter{
		client:  &http.Client{Timeout: 10 * time.Second},
		baseURL: baseURL,
		dbName:  dbName,
		user:    user,
		pass:    pass,
	}
	// ensure DB exists
	if err := c.ensureDB(); err != nil {
		return nil, err
	}
	// ensure required Mango indexes exist (needed for sorted _find used by nextID)
	if err := c.ensureIndexes(); err != nil {
		return nil, err
	}
	return c, nil
}

func (c *CouchAdapter) url(path string) string {
	// handle empty baseURL defensively (should not normally happen)
	if c.baseURL == "" {
		return path
	}
	// baseURL may or may not end with /
	if strings.HasSuffix(c.baseURL, "/") {
		return c.baseURL + path
	}
	return c.baseURL + "/" + path
}

func (c *CouchAdapter) doRequest(method, path string, body interface{}) (*http.Response, error) {
	var r io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		r = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, c.url(path), r)
	if err != nil {
		return nil, err
	}
	if c.user != "" || c.pass != "" {
		req.SetBasicAuth(c.user, c.pass)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, err
	}
	return resp, nil
}

func (c *CouchAdapter) ensureDB() error {
	// PUT /{db}
	resp, err := c.doRequest("PUT", c.dbName, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// 201 created or 412 already exists (or 200)
	if resp.StatusCode == 201 || resp.StatusCode == 412 || resp.StatusCode == 200 {
		return nil
	}
	b, _ := io.ReadAll(resp.Body)
	return fmt.Errorf("ensureDB failed: %s: %s", resp.Status, string(b))
}

// ensureIndexes creates necessary Mango indexes used by the adapter. It's safe to call
// repeatedly; if the index already exists CouchDB will return a non-error response.
func (c *CouchAdapter) ensureIndexes() error {
	// Create a Mango index suitable for sorting by "id" (desc) while selecting by "type".
	// CouchDB requires a single sort direction for all fields in a multi-field sort.
	// Create an index with both fields descending to match nextID() which sorts by id desc.
	idx := map[string]interface{}{
		"index": map[string]interface{}{
			"fields": []interface{}{
				map[string]string{"type": "desc"},
				map[string]string{"id": "desc"},
			},
		},
		"name": "idx_type_id_desc",
		"type": "json",
		"ddoc": "ddoc_idx_type_id_desc",
	}
	resp, err := c.doRequest("POST", c.dbName+"/_index", idx)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// Accept 200/201 as success. For other 4xx/5xx return error.
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ensureIndexes failed: %s: %s", resp.Status, string(b))
	}
	return nil
}

// internal types for CouchDB docs
type couchShishaDoc struct {
	DocID        string       `json:"_id,omitempty"`
	Rev          string       `json:"_rev,omitempty"`
	Type         string       `json:"type"`
	ID           uint         `json:"id"`
	Name         string       `json:"name"`
	Flavor       string       `json:"flavor"`
	Manufacturer Manufacturer `json:"manufacturer"`
	Smoked       int          `json:"smoked,omitempty"`
	Ratings      []Rating     `json:"ratings,omitempty"`
	Comments     []Comment    `json:"comments,omitempty"`
}

// helper: find doc by numeric id via _find
func (c *CouchAdapter) findByNumericID(id uint) (*couchShishaDoc, error) {
	selector := map[string]interface{}{
		"selector": map[string]interface{}{
			"type": "shisha",
			"id":   id,
		},
		"limit": 1,
	}
	resp, err := c.doRequest("POST", c.dbName+"/_find", selector)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("findByNumericID failed: %s: %s", resp.Status, string(b))
	}
	var out struct {
		Docs []couchShishaDoc `json:"docs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	if len(out.Docs) == 0 {
		return nil, nil
	}
	return &out.Docs[0], nil
}

func (c *CouchAdapter) ListShishas() ([]Shisha, error) {
	log.Printf("couchdb ListShishas: starting _find db=%s", c.dbName)
	// Use _find with selector type=shisha
	selector := map[string]interface{}{
		"selector": map[string]interface{}{
			"type": "shisha",
		},
		"limit": 1000,
	}
	resp, err := c.doRequest("POST", c.dbName+"/_find", selector)
	if err != nil {
		log.Printf("couchdb ListShishas: request error: %v", err)
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		log.Printf("couchdb ListShishas: _find failed status=%s body=%s", resp.Status, string(b))
		return nil, fmt.Errorf("ListShishas _find failed: %s: %s", resp.Status, string(b))
	}
	var out struct {
		Docs []couchShishaDoc `json:"docs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		log.Printf("couchdb ListShishas: decode error: %v", err)
		return nil, err
	}
	res := make([]Shisha, 0, len(out.Docs))
	for _, d := range out.Docs {
		res = append(res, Shisha{
			ID:           d.ID,
			Name:         d.Name,
			Flavor:       d.Flavor,
			Manufacturer: d.Manufacturer,
			Smoked:       d.Smoked,
			Ratings:      d.Ratings,
			Comments:     d.Comments,
		})
	}
	log.Printf("couchdb ListShishas: returning %d docs", len(res))
	return res, nil
}

func (c *CouchAdapter) GetShisha(id uint) (*Shisha, error) {
	doc, err := c.findByNumericID(id)
	if err != nil {
		return nil, err
	}
	if doc == nil {
		return nil, nil
	}
	s := &Shisha{
		ID:           doc.ID,
		Name:         doc.Name,
		Flavor:       doc.Flavor,
		Manufacturer: doc.Manufacturer,
		Smoked:       doc.Smoked,
		Ratings:      doc.Ratings,
		Comments:     doc.Comments,
	}
	return s, nil
}

// helper to find highest numeric id to allocate next id
func (c *CouchAdapter) nextID() (uint, error) {
	// selector type=shisha sort by id desc limit 1
	payload := map[string]interface{}{
		"selector": map[string]interface{}{
			"type": "shisha",
		},
		"sort": []map[string]string{
			{"id": "desc"},
		},
		"limit": 1,
	}
	resp, err := c.doRequest("POST", c.dbName+"/_find", payload)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return 0, fmt.Errorf("nextID _find failed: %s: %s", resp.Status, string(b))
	}
	var out struct {
		Docs []couchShishaDoc `json:"docs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return 0, err
	}
	if len(out.Docs) == 0 {
		return 1, nil
	}
	return out.Docs[0].ID + 1, nil
}

func (c *CouchAdapter) CreateShisha(s *Shisha) (*Shisha, error) {
	if s == nil {
		return nil, errors.New("nil shisha")
	}
	nid, err := c.nextID()
	if err != nil {
		return nil, err
	}
	s.ID = nid
	doc := couchShishaDoc{
		Type:         "shisha",
		ID:           s.ID,
		Name:         s.Name,
		Flavor:       s.Flavor,
		Manufacturer: s.Manufacturer,
		Smoked:       s.Smoked,
		Ratings:      s.Ratings,
		Comments:     s.Comments,
	}
	resp, err := c.doRequest("POST", c.dbName, doc)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("CreateShisha failed: %s: %s", resp.Status, string(b))
	}
	// success, return created
	return s, nil
}

func (c *CouchAdapter) UpdateShisha(id uint, s *Shisha) (*Shisha, error) {
	if s == nil {
		return nil, errors.New("nil shisha")
	}
	doc, err := c.findByNumericID(id)
	if err != nil {
		return nil, err
	}
	if doc == nil {
		return nil, errors.New("not found")
	}
	// update fields and PUT doc
	doc.Name = s.Name
	doc.Flavor = s.Flavor
	doc.Manufacturer = s.Manufacturer
	doc.Smoked = s.Smoked
	doc.Ratings = s.Ratings
	doc.Comments = s.Comments

	path := fmt.Sprintf("%s/%s", c.dbName, doc.DocID)
	resp, err := c.doRequest("PUT", path, doc)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("UpdateShisha failed: %s: %s", resp.Status, string(b))
	}
	return s, nil
}

func (c *CouchAdapter) DeleteShisha(id uint) error {
	doc, err := c.findByNumericID(id)
	if err != nil {
		return err
	}
	if doc == nil {
		return nil
	}
	path := fmt.Sprintf("%s/%s?rev=%s", c.dbName, doc.DocID, doc.Rev)
	resp, err := c.doRequest("DELETE", path, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("DeleteShisha failed: %s: %s", resp.Status, string(b))
	}
	return nil
}

func (c *CouchAdapter) AddRating(id uint, user string, score int) error {
	doc, err := c.findByNumericID(id)
	if err != nil {
		return err
	}
	if doc == nil {
		return errors.New("not found")
	}
	r := Rating{User: user, Score: score, Timestamp: time.Now().Unix()}
	doc.Ratings = append(doc.Ratings, r)
	path := fmt.Sprintf("%s/%s", c.dbName, doc.DocID)
	resp, err := c.doRequest("PUT", path, doc)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("AddRating failed: %s: %s", resp.Status, string(b))
	}
	return nil
}

func (c *CouchAdapter) AddComment(id uint, user, message string) error {
	doc, err := c.findByNumericID(id)
	if err != nil {
		return err
	}
	if doc == nil {
		return errors.New("not found")
	}
	cm := Comment{User: user, Message: message}
	doc.Comments = append(doc.Comments, cm)
	path := fmt.Sprintf("%s/%s", c.dbName, doc.DocID)
	resp, err := c.doRequest("PUT", path, doc)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("AddComment failed: %s: %s", resp.Status, string(b))
	}
	return nil
}

func (c *CouchAdapter) AddSmoked(id uint) error {
	doc, err := c.findByNumericID(id)
	if err != nil {
		return err
	}
	if doc == nil {
		return errors.New("not found")
	}
	doc.Smoked = doc.Smoked + 1
	path := fmt.Sprintf("%s/%s", c.dbName, doc.DocID)
	resp, err := c.doRequest("PUT", path, doc)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("AddSmoked failed: %s: %s", resp.Status, string(b))
	}
	return nil
}
