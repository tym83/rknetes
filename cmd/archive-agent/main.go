package main

import (
	"context"
	"flag"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"log"
	"os"
	"os/signal"
	"rknetes.su/rknetes/pkg/archive"
	"rknetes.su/rknetes/pkg/cluster"
	"syscall"
	"time"
)

func main() {
	config := flag.String("kubeconfig", "", "nested kubeconfig")
	ns := flag.String("namespace", os.Getenv("POD_NAMESPACE"), "lab namespace")
	pod := flag.String("pod", os.Getenv("POD_NAME"), "collector Pod")
	policy := flag.String("policy", "", "ArchivePolicy name")
	directory := flag.String("directory", "/archive/"+os.Getenv("POD_UID"), "private archive directory")
	iface := flag.String("interface", "eth0", "Pod interface")
	relay := flag.String("hubble", "hubble-relay.kube-system.svc:80", "nested Hubble relay")
	flag.Parse()
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	c, err := cluster.New(*config, "admin@workshop")
	if err != nil {
		log.Fatal(err)
	}
	p, err := c.R("archivepolicies", *ns).Get(ctx, *policy, metav1.GetOptions{})
	if err != nil {
		log.Fatal(err)
	}
	store, err := archive.Open(*directory, cluster.Int(p.Object, 256<<20, "spec", "maxBytes"), time.Duration(cluster.Int(p.Object, 180, "spec", "retentionDays"))*24*time.Hour)
	if err != nil {
		log.Fatal(err)
	}
	agent := archive.Agent{C: c, Namespace: *ns, Pod: *pod, Policy: *policy, Interface: *iface, Relay: *relay, Store: store}
	if err := agent.Run(ctx); err != nil {
		log.Fatal(err)
	}
}
