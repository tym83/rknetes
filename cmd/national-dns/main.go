package main

import (
	"flag"
	"log"
	"rknetes.su/rknetes/pkg/nationaldns"
)

func main() {
	dns := flag.String("dns-listen", ":1053", "lab DNS TCP/UDP listener; empty disables")
	ntp := flag.String("ntp-listen", "", "optional lab NTP UDP listener")
	config := flag.String("config", "/config/zones.json", "lab zones and upstream")
	flag.Parse()
	errors := make(chan error, 2)
	if *dns != "" {
		go func() { errors <- nationaldns.ServeDNS(*dns, *config) }()
	}
	if *ntp != "" {
		go func() { errors <- nationaldns.ServeNTP(*ntp) }()
	}
	if *dns == "" && *ntp == "" {
		log.Fatal("a lab listener is required")
	}
	log.Fatal(<-errors)
}
