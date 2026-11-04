package main

import (
	"context"
	"flag"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/maxlet"
	"rknetes.su/rknetes/pkg/presentation"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested kubeconfig")
	ctx := flag.String("context", "admin@workshop", "context")
	ns := flag.String("namespace", "", "one lab namespace")
	listen := flag.String("listen", ":9443", "listen address")
	cert := flag.String("tls-cert", "/tls/tls.crt", "server certificate")
	key := flag.String("tls-key", "/tls/tls.key", "server key")
	ca := flag.String("client-ca", "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", "cluster client CA")
	flag.Parse()
	if *ns == "" {
		log.Fatal("a lab namespace is required")
	}
	c, err := cluster.New(*kubeconfig, *ctx)
	if err != nil {
		log.Fatal(err)
	}
	handler, err := presentation.New(c, *ns)
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal(maxlet.ServeHandler(context.Background(), c, *listen, *cert, *key, *ca, handler))
}
