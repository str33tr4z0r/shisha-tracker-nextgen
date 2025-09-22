package storage

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
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
	// default to cluster Service DNS (shisha-couchdb) when env not set
	if baseURL == "" {
		baseURL = "http://shisha-couchdb:5984"
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

// internal types for CouchDB docs
type couchShishaDoc struct {
	DocID        string       `json:"_id,omitempty"`
	Rev          string       `json:"_rev,omitempty"`
	Type         string       `json:"type"`
	ID           uint         `json:"id"`
	Name         string       `json:"name"`
	Flavor       string       `json:"flavor"`
	Manufacturer Manufacturer `json:"manufacturer"`
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
	// Use _find with selector type=shisha
	selector := map[string]interface{}{
		"selector": map[string]interface{}{
			"type": "shisha",
		},
		"limit": 1000,
	}
	resp, err := c.doRequest("POST", c.dbName+"/_find", selector)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ListShishas _find failed: %s: %s", resp.Status, string(b))
	}
	var out struct {
		Docs []couchShishaDoc `json:"docs"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, err
	}
	var res []Shisha
	for _, d := range out.Docs {
		res = append(res, Shisha{
			ID:           d.ID,
			Name:         d.Name,
			Flavor:       d.Flavor,
			Manufacturer: d.Manufacturer,
			Ratings:      d.Ratings,
			Comments:     d.Comments,
		})
	}
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

// ClusterStatus queries CouchDB _membership and returns whether the node is
// part of a configured cluster and which nodes are members. When CouchDB is
// not clustered, the cluster_nodes field usually contains ["nonode@nohost"].
func (c *CouchAdapter) ClusterStatus() (clustered bool, clusterNodes []string, allNodes []string, err error) {
	resp, err := c.doRequest("GET", "_membership", nil)
	if err != nil {
		return false, nil, nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		b, _ := io.ReadAll(resp.Body)
		return false, nil, nil, fmt.Errorf("_membership request failed: %s: %s", resp.Status, string(b))
	}
	var out struct {
		AllNodes     []string `json:"all_nodes"`
		ClusterNodes []string `json:"cluster_nodes"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return false, nil, nil, err
	}
	// Detect uninitialized cluster
	if len(out.ClusterNodes) == 1 && out.ClusterNodes[0] == "nonode@nohost" {
		return false, nil, out.AllNodes, nil
	}
	return true, out.ClusterNodes, out.AllNodes, nil
}
