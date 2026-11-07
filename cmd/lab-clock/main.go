package main

import (
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"rknetes.su/rknetes/pkg/nationaldns"
	"time"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	ntp := flag.String("ntp", "", "literal lab reference clock address")
	offset := flag.Duration("unsynced-offset", 0, "controlled application clock offset only if NTP fails")
	ca := flag.String("ca", "", "lab TLS CA file")
	name := flag.String("tls-name", "domestic.lab", "lab certificate name")
	endpoint := flag.String("url", "", "literal lab HTTPS endpoint")
	flag.Parse()
	u, err := url.Parse(*endpoint)
	if err != nil || u.Scheme != "https" || u.User != nil {
		return fmt.Errorf("lab HTTPS URL required")
	}
	if err := nationaldns.LabAddress(u.Host); err != nil {
		return err
	}
	now, err := nationaldns.Clock(*ntp)
	if err != nil {
		if *offset == 0 {
			return fmt.Errorf("NTP unavailable: %w", err)
		}
		now = time.Now().Add(*offset)
		fmt.Println("NTP unavailable; controlled application clock offset:", *offset)
	} else {
		fmt.Println("Actual lab NTP response received")
	}
	data, err := os.ReadFile(*ca)
	if err != nil {
		return err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(data) {
		return fmt.Errorf("empty lab CA")
	}
	client := &http.Client{Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }, Transport: &http.Transport{TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: pool, ServerName: *name, Time: func() time.Time { return now }}}}
	response, err := client.Get(*endpoint)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("HTTPS returned%d", response.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 4096))
	if err != nil {
		return err
	}
	fmt.Printf("PASS: actual TLS exchange at controlled time%s, bytes=%d\n", now.UTC().Format(time.RFC3339), len(body))
	return nil
}
