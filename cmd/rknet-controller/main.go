package main

import (
	"context"
	"flag"
	"log"
	"os/signal"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/controller"
	"syscall"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested cluster kubeconfig; empty uses the pod service account")
	contextName := flag.String("context", "admin@workshop", "context in the nested cluster kubeconfig")
	namespace := flag.String("namespace", "", "manage one lab namespace; empty manages non-independent labs")
	flag.Parse()
	c, err := cluster.New(*kubeconfig, *contextName)
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := (&controller.Controller{C: c, Namespace: *namespace}).Run(ctx); err != nil {
		log.Fatal(err)
	}
}
