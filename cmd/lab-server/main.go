package main

import (
	"bytes"
	"flag"
	"io"
	"log"
	"net"
	"net/http"
	"time"
)

// The small health check and the large raw transfer are independent real paths.
func main() {
	listen := flag.String("listen", ":8080", "HTTP health listener")
	flag.Parse()
	go func() {
		listener, err := net.Listen("tcp", ":8081")
		if err != nil {
			log.Fatal(err)
		}
		for {
			conn, err := listener.Accept()
			if err != nil {
				log.Print(err)
				continue
			}
			go func(c net.Conn) {
				defer c.Close()
				_ = c.(*net.TCPConn).SetNoDelay(true)
				payload := bytes.Repeat([]byte{'x'}, 1024)
				for i := 0; i < 64; i++ {
					if _, err := c.Write(payload); err != nil {
						return
					}
					time.Sleep(10 * time.Millisecond)
				}
				// Leave the socket open so the test observes a stall, not an EOF.
				time.Sleep(time.Minute)
			}(conn)
		}
	}()
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "ok") })
	http.HandleFunc("/telegram", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "🛩") })
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "lab application") })
	log.Fatal(http.ListenAndServe(*listen, nil))
}
