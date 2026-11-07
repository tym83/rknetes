// The domestic module mirror retains upstream module bytes and checksum semantics.
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

func main() {
	listen := flag.String("listen", "127.0.0.1:18085", "private listener")
	directory := flag.String("cache", "/work/go-mirror", "bounded cache")
	offline := flag.Bool("offline", false, "serve only stored upstream bytes")
	flag.Parse()
	if err := os.MkdirAll(*directory, 0700); err != nil {
		log.Fatal(err)
	}
	var mu sync.Mutex
	client := &http.Client{Timeout: time.Minute}
	server := &http.Server{Addr: *listen, ReadHeaderTimeout: 5 * time.Second, Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" || strings.Contains(r.URL.Path, "..") || r.URL.RawQuery != "" {
			http.Error(w, "module GET required", 400)
			return
		}
		digest := sha256.Sum256([]byte(r.URL.EscapedPath()))
		path := filepath.Join(*directory, hex.EncodeToString(digest[:]))
		mu.Lock()
		defer mu.Unlock()
		if data, err := os.ReadFile(path); err == nil {
			w.Header().Set("X-Goshran-Cache", "HIT")
			w.Write(data)
			return
		}
		if *offline {
			http.Error(w, "uncached module", 404)
			return
		}
		response, err := client.Get("https://proxy.golang.org" + r.URL.EscapedPath())
		if err != nil {
			http.Error(w, err.Error(), 502)
			return
		}
		defer response.Body.Close()
		data, err := io.ReadAll(io.LimitReader(response.Body, (128<<20)+1))
		if err != nil || len(data) > 128<<20 {
			http.Error(w, "bounded module size exceeded", 502)
			return
		}
		if response.StatusCode != 200 {
			w.WriteHeader(response.StatusCode)
			w.Write(data)
			return
		}
		entries, _ := os.ReadDir(*directory)
		var bytes int64
		for _, e := range entries {
			info, _ := e.Info()
			bytes += info.Size()
		}
		if bytes+int64(len(data)) > 512<<20 {
			http.Error(w, "domestic cache is full", 507)
			return
		}
		if err := os.WriteFile(path, data, 0600); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		fmt.Printf("upstream %s bytes=%d sha256=%x\n", r.URL.Path, len(data), sha256.Sum256(data))
		w.Header().Set("X-Goshran-Cache", "MISS")
		w.Write(data)
	})}
	log.Fatal(server.ListenAndServe())
}
