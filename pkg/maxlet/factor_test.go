package maxlet

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestFactorBindsCertificateRejectsReplayAndExpires(t *testing.T) {
	now := time.Unix(1700000000, 0)
	f := &Factor{Secret: []byte("12345678901234567890"), TTL: 3 * time.Second, Now: func() time.Time { return now }}
	request := func(path, body, cert, token string) (bool, *httptest.ResponseRecorder) {
		r := httptest.NewRequest("POST", path, strings.NewReader(body))
		r.TLS = &tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{{Raw: []byte(cert)}}}}
		r.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		allowed := f.authorize(w, r)
		return allowed, w
	}
	body := `{"code":"` + Code(f.Secret, now) + `"}`
	_, w := request("/session", body, "alice", "")
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	var result map[string]string
	json.Unmarshal(w.Body.Bytes(), &result)
	if _, w := request("/session", body, "alice", ""); w.Code != 401 {
		t.Fatal("accepted replay")
	}
	if ok, _ := request("/api/v1", "", "alice", result["token"]); !ok {
		t.Fatal("valid session rejected")
	}
	if ok, _ := request("/api/v1", "", "mallory", result["token"]); ok {
		t.Fatal("accepted another certificate")
	}
	now = now.Add(4 * time.Second)
	if ok, _ := request("/api/v1", "", "alice", result["token"]); ok {
		t.Fatal("accepted expired session")
	}
}

func TestRFC6238Vector(t *testing.T) {
	if got := Code([]byte("12345678901234567890"), time.Unix(59, 0)); got != "287082" {
		t.Fatal(got)
	}
}
