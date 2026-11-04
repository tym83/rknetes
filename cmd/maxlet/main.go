package main

import (
	"context"
	"flag"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/maxlet"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested kubeconfig")
	ctx := flag.String("context", "admin@workshop", "context")
	listen := flag.String("listen", ":9443", "listen address")
	cert := flag.String("tls-cert", "/tls/tls.crt", "server certificate")
	key := flag.String("tls-key", "/tls/tls.key", "server key")
	ca := flag.String("client-ca", "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", "cluster client CA")
	archive := flag.String("archive", "/archive", "session archive")
	flag.Parse()
	c, err := cluster.New(*kubeconfig, *ctx)
	if err != nil {
		log.Fatal(err)
	}
	log.Fatal(maxlet.Serve(context.Background(), c, *listen, *cert, *key, *ca, *archive))
}
