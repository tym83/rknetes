package goshran

import (
	"io"
	"net/http"
	"net/http/httptest"
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
