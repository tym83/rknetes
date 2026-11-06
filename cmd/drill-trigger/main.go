package main

import (
	"context"
	"flag"
	"log"
	"rknetes.su/rknetes/pkg/cluster"
	"time"
)

func main() {
	ns := flag.String("namespace", "", "selected lab namespace")
	name := flag.String("name", "", "selected drill")
	duration := flag.Duration("duration", 5*time.Minute, "isolation duration")
	flag.Parse()
	if *duration < time.Second || *duration > time.Hour {
		log.Fatal("duration must be1second..1hour")
	}
	c, err := cluster.New("", "admin@workshop")
	if err != nil {
		log.Fatal(err)
	}
	ctx := context.Background()
	if err := c.Guard(ctx); err != nil {
		log.Fatal(err)
	}
	if err := c.Patch(ctx, "sovereigntydrills", *ns, *name, cluster.Map{"spec": cluster.Map{"enabled": true}}); err != nil {
		log.Fatal(err)
	}
	log.Print("Quarterly sovereignty drill started")
	time.Sleep(*duration)
	if err := c.Patch(ctx, "sovereigntydrills", *ns, *name, cluster.Map{"spec": cluster.Map{"enabled": false}}); err != nil {
		log.Fatal(err)
	}
	log.Print("Учения прошли успешно")
}
