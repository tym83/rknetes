package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os/signal"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/controller"
	"syscall"
	"time"
)

func main() {
	kubeconfig := flag.String("kubeconfig", "", "nested cluster kubeconfig; empty uses the pod service account")
	contextName := flag.String("context", "admin@workshop", "context in the nested cluster kubeconfig")
	namespace := flag.String("namespace", "", "manage one lab namespace; empty manages non-independent labs")
	metrics := flag.String("metrics-listen", "", "optional metrics listener")
	flag.Parse()
	c, err := cluster.New(*kubeconfig, *contextName)
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	controller := &controller.Controller{C: c, Namespace: *namespace}
	if *metrics != "" {
		server := &http.Server{Addr: *metrics, Handler: http.HandlerFunc(controller.Metrics), ReadHeaderTimeout: 3 * time.Second}
		defer server.Close()
		go func() {
			if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Printf("metrics: %v", err)
				cancel()
			}
		}()
	}
	if err := controller.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
