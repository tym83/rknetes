package main

import (
	"context"
	"flag"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/maxlet"
	"rknetes.su/rknetes/pkg/watchoffice"
)

func main() {
	config := flag.String("kubeconfig", "", "nested kubeconfig")
	contextName := flag.String("context", "admin@workshop", "context")
	listen := flag.String("listen", ":9443", "listen address")
	cert := flag.String("tls-cert", "/tls/tls.crt", "server certificate")
	key := flag.String("tls-key", "/tls/tls.key", "server key")
	ca := flag.String("client-ca", "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", "client CA")
	flag.Parse()
	c, err := cluster.New(*config, *contextName)
	if err != nil {
		log.Fatal(err)
	}
	handler, err := watchoffice.New(c)
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal(maxlet.ServeHandler(context.Background(), c, *listen, *cert, *key, *ca, handler))
}
