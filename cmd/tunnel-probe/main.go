package main

import (
	"flag"
	"log"
	"net/http"
	"time"

	"rknetes.su/rknetes/pkg/tunnelprobe"
)

func main() {
	config := flag.String("config", "/runtime/probes.json", "explicit lab protocol driver routes")
	listen := flag.String("listen", ":7777", "probe control address")
	flag.Parse()
	log.Fatal((&http.Server{Addr: *listen, Handler: tunnelprobe.Server{Config: *config}, ReadHeaderTimeout: 3 * time.Second}).ListenAndServe())
}
