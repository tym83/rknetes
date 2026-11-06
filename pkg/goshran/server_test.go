package goshran

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestManifestBytesRedirectAndAbsoluteChartURL(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Docker-Content-Digest", "sha256:unchanged")
		io.WriteString(w, `{"schemaVersion":2}`)
	}))
	defer upstream.Close()
	index := []byte("entries:\n  chart:\n  - urls: [https://foreign.example/chart.tgz]\n")
	server, err := New(upstream.URL, index)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		path string
		code int
		body string
	}{
		{"/v2/library/postgres/manifests/17", 200, `{"schemaVersion":2}`},
		{"/index.yaml", 200, string(index)},
		{"/v2/library/postgres/blobs/sha256:abc", 307, ""},
	} {
		w := httptest.NewRecorder()
		server.ServeHTTP(w, httptest.NewRequest("GET", tc.path, nil))
		if w.Code != tc.code {
			t.Fatalf("%s: %d", tc.path, w.Code)
		}
		if tc.body != "" && w.Body.String() != tc.body {
			t.Fatalf("content changed at %s", tc.path)
		}
		if tc.code == 307 && w.Header().Get("Location") != upstream.URL+tc.path {
			t.Fatalf("blob redirect lost upstream path")
		}
	}
}

func TestSharedQuotaRefusalCarriesStatement(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		io.WriteString(w, `{"errors":[{"code":"TOOMANYREQUESTS"}]}`)
	}))
	defer upstream.Close()
	server, err := New(upstream.URL, nil)
	if err != nil {
		t.Fatal(err)
	}
	w := httptest.NewRecorder()
	server.ServeHTTP(w, httptest.NewRequest("GET", "/v2/library/postgres/manifests/17", nil))
	if w.Code != http.StatusTooManyRequests || w.Header().Get("X-Goshran-Statement") == "" || !strings.Contains(w.Body.String(), "TOOMANYREQUESTS") {
		t.Fatalf("refusal not passed through with statement: %d %v", w.Code, w.Header())
	}
}

func TestVendorWithdrawalIsModernization(t *testing.T) {
	gone := false
	vendor := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if gone {
			w.WriteHeader(http.StatusGone)
			return
		}
		io.WriteString(w, "chart")
	}))
	defer vendor.Close()
	index := []byte("entries:\n  chart:\n  - urls: [" + vendor.URL + "/chart.tgz]\n")
	server, err := New("https://registry.example", index)
	if err != nil {
		t.Fatal(err)
	}
	status := func() (int, string) {
		w := httptest.NewRecorder()
		server.ServeHTTP(w, httptest.NewRequest("GET", "/status", nil))
		return w.Code, w.Body.String()
	}
	if code, _ := status(); code != 200 {
		t.Fatalf("vendor present but status %d", code)
	}
	gone = true
	if code, body := status(); code != 503 || !strings.Contains(body, "модернизацию") {
		t.Fatalf("vendor gone but status %d %q", code, body)
	}
	w := httptest.NewRecorder()
	server.ServeHTTP(w, httptest.NewRequest("GET", "/index.yaml", nil))
	if w.Body.String() != string(index) {
		t.Fatal("copied index must stay unchanged after the vendor leaves")
	}
}
