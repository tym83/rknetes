package main

import (
	"context"
	"flag"
	"log"
	"os"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/maxlet"
	"time"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested kubeconfig")
	ctx := flag.String("context", "admin@workshop", "context")
	listen := flag.String("listen", ":9443", "listen address")
	cert := flag.String("tls-cert", "/tls/tls.crt", "server certificate")
	key := flag.String("tls-key", "/tls/tls.key", "server key")
	ca := flag.String("client-ca", "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", "cluster client CA")
	archive := flag.String("archive", "/archive", "session archive")
	factor := flag.String("second-factor-secret", "", "optional private raw TOTP secret file")
	ttl := flag.Duration("session-ttl", 5*time.Minute, "second-factor session lifetime")
	enrollment := flag.String("enrollment-namespace", "", "lab namespace containing the MAX enrollment ledger")
	events := flag.Bool("events", true, "archive all nested cluster Events privately")
	definitions := flag.Bool("lab-definitions", false, "opt-in lab.rknetes.su definition transport experiment")
	flag.Parse()
	c, err := cluster.New(*kubeconfig, *ctx)
	if err != nil {
		log.Fatal(err)
	}
	handler, err := maxlet.New(c, *archive)
	if err != nil {
		log.Fatal(err)
	}
	handler.EnrollmentNamespace = *enrollment
	handler.LabDefinitions = *definitions
	if *factor != "" {
		secret, err := os.ReadFile(*factor)
		if err != nil || len(secret) < 16 {
			log.Fatal("second factor requires a private secret of at least16bytes")
		}
		handler.Factor = &maxlet.Factor{Secret: secret, TTL: *ttl}
	}
	if *events {
		go func() {
			if err := maxlet.ArchiveEvents(context.Background(), c, *archive); err != nil {
				log.Printf("event archive: %v", err)
			}
		}()
	}
	log.Fatal(maxlet.ServeHandler(context.Background(), c, *listen, *cert, *key, *ca, handler))
}
