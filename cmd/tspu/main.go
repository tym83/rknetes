package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"rknetes.su/rknetes/pkg/cluster"
	"rknetes.su/rknetes/pkg/tspu"
	"syscall"
)

func main() {
	node := flag.String("node", os.Getenv("NODE_NAME"), "nested node identity")
	socket := flag.String("socket", "/run/containerd/containerd.sock", "containerd CRI socket")
	object := flag.String("object", "/rk/tspu.o", "compiled byte-policy object")
	selfTest := flag.Bool("self-test", false, "execute boundary and sequence tests in the kernel without attaching")
	flag.Parse()
	if *selfTest {
		if err := tspu.KernelCheck(*object); err != nil {
			log.Fatal(err)
		}
		return
	}
	c, err := cluster.New("", "")
	if err != nil {
		log.Fatal(err)
	}
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := (&tspu.Agent{C: c, Node: *node, Socket: *socket, Object: *object}).Run(ctx); err != nil {
		log.Fatal(err)
	}
}
