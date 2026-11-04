package main

import (
	"flag"
	"log"
	"net/http"
	"os"
	"rknetes.su/rknetes/pkg/goshran"
	"time"
)

func main() {
	listen := flag.String("listen", ":8080", "listen address")
	upstream := flag.String("upstream", "https://registry-1.docker.io", "upstream registry")
	index := flag.String("index", "/etc/goshran/index.yaml", "unmodified upstream Helm index")
	flag.Parse()
	data, err := os.ReadFile(*index)
	if err != nil {
		log.Fatal(err)
	}
	handler, err := goshran.New(*upstream, data)
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal((&http.Server{Addr: *listen, Handler: handler, ReadHeaderTimeout: 10 * time.Second}).ListenAndServe())
}
