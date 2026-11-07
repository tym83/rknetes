package maxlet

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

type session struct {
	Certificate string
	Expires     time.Time
}
type Factor struct {
	Secret   []byte
	TTL      time.Duration
	Now      func() time.Time
	mu       sync.Mutex
	used     map[string]int64
	sessions map[string]session
}

func Code(secret []byte, now time.Time) string {
	var counter [8]byte
	binary.BigEndian.PutUint64(counter[:], uint64(now.Unix()/30))
	h := hmac.New(sha1.New, secret)
	h.Write(counter[:])
	sum := h.Sum(nil)
	offset := sum[len(sum)-1] & 15
	return fmt.Sprintf("%06d", (binary.BigEndian.Uint32(sum[offset:offset+4])&0x7fffffff)%1000000)
}

func (f *Factor) authorize(w http.ResponseWriter, r *http.Request) bool {
	if f == nil {
		return true
	}
	now := time.Now()
	if f.Now != nil {
		now = f.Now()
	}
	digest := sha256.Sum256(r.TLS.VerifiedChains[0][0].Raw)
	identity := hex.EncodeToString(digest[:])
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.sessions == nil {
		f.sessions = map[string]session{}
		f.used = map[string]int64{}
	}
	for token, s := range f.sessions {
		if !now.Before(s.Expires) {
			delete(f.sessions, token)
		}
	}
	for cert, step := range f.used {
		if step < now.Unix()/30-1 {
			delete(f.used, cert)
		}
	}
	if r.URL.Path == "/session" {
		if r.Method != "POST" {
			http.Error(w, "POST required", 405)
			return false
		}
		var body struct {
			Code string `json:"code"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1024)).Decode(&body); err != nil {
			http.Error(w, "invalid factor request", 400)
			return false
		}
		step := int64(-1)
		for shift := -1; shift <= 1; shift++ {
			at := now.Add(time.Duration(shift) * 30 * time.Second)
			if hmac.Equal([]byte(body.Code), []byte(Code(f.Secret, at))) {
				step = at.Unix() / 30
				break
			}
		}
		if len(f.Secret) < 16 || step < 0 || f.used[identity] >= step {
			http.Error(w, "second factor invalid or already used", 401)
			return false
		}
		if len(f.sessions) >= 4096 {
			http.Error(w, "session capacity reached", 503)
			return false
		}
		var random [32]byte
		if _, err := rand.Read(random[:]); err != nil {
			http.Error(w, "session unavailable", 503)
			return false
		}
		token := hex.EncodeToString(random[:])
		ttl := f.TTL
		if ttl <= 0 {
			ttl = 5 * time.Minute
		}
		expires := now.Add(ttl)
		f.sessions[token] = session{Certificate: identity, Expires: expires}
		f.used[identity] = step
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		json.NewEncoder(w).Encode(map[string]interface{}{"token": token, "expires": expires})
		return false
	}
	token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	s, ok := f.sessions[token]
	if !ok || s.Certificate != identity || !now.Before(s.Expires) {
		http.Error(w, "MAX second-factor session required", 401)
		return false
	}
	return true
}
