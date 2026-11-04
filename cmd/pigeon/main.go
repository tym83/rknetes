package main

import (
	"context"
	"flag"
	"log"
	"os/signal"
	"rknetes.su/rknetes/pkg/pigeon"
	"syscall"
	"time"
)

func main() {
	spool := flag.String("spool", "/spool", "mounted PVC")
	dest := flag.String("destination", "", "destination namespace")
	delay := flag.Duration("delay", 3*time.Minute, "flight duration")
	loss := flag.Int("loss", 55, "packet loss percent")
	flag.Parse()
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	if err := pigeon.Run(ctx, *spool, *dest, *delay, *loss); err != nil {
		log.Fatal(err)
	}
}
