package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"rknetes.su/rknetes/pkg/admission"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested cluster kubeconfig")
	contextName := flag.String("context", "admin@workshop", "nested context")
	cert := flag.String("tls-cert", "/tls/tls.crt", "serving certificate")
	key := flag.String("tls-key", "/tls/tls.key", "serving key")
	listen := flag.String("listen", ":9443", "listen address")
	flag.Parse()
	c, err := cluster.New(*kubeconfig, *contextName)
	if err != nil {
		log.Fatal(err)
	}
	if err := c.Guard(context.Background()); err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Addr: *listen, Handler: &admission.Server{C: c}, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(server.ListenAndServeTLS(*cert, *key))
}
