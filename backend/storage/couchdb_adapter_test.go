package storage

import (
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestURLJoin(t *testing.T) {
	c := &CouchAdapter{baseURL: "http://example.com/"}
	got := c.url("db")
	want := "http://example.com/db"
	if got != want {
		t.Fatalf("expected %q got %q", want, got)
	}

	c.baseURL = "http://example.com"
	got = c.url("db")
	if got != want {
		t.Fatalf("expected %q got %q", want, got)
	}

	c.baseURL = ""
	got = c.url("db")
	if got != "db" {
		t.Fatalf("expected %q got %q", "db", got)
	}
}

func TestNewCouchAdapter_EnsureDB(t *testing.T) {
	// Mock CouchDB server that accepts PUT /shisha and returns 201
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPut {
			t.Fatalf("expected PUT method, got %s", r.Method)
		}
		if r.URL.Path != "/shisha" {
			t.Fatalf("expected path /shisha, got %s", r.URL.Path)
		}
		w.WriteHeader(http.StatusCreated)
	}))
	defer ts.Close()

	// set env so NewCouchAdapter uses our test server
	if err := os.Setenv("COUCHDB_URL", ts.URL); err != nil {
		t.Fatalf("failed to set env: %v", err)
	}
	// ensure other envs unset to exercise defaults
	_ = os.Unsetenv("COUCHDB_USER")
	_ = os.Unsetenv("COUCHDB_PASSWORD")
	_ = os.Unsetenv("COUCHDB_DB")

	defer func() {
		_ = os.Unsetenv("COUCHDB_URL")
	}()

	c, err := NewCouchAdapter("", "", "", "")
	if err != nil {
		t.Fatalf("NewCouchAdapter failed: %v", err)
	}
	if c == nil {
		t.Fatalf("expected non-nil adapter")
	}
	if c.baseURL != ts.URL {
		t.Fatalf("expected baseURL %q got %q", ts.URL, c.baseURL)
	}
}
