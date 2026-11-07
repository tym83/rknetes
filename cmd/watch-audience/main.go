// watch-audience holds a measured audience through the authenticated gateway.
package main

import (
	"context"
	"crypto/x509"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/rest"
	"rknetes.su/rknetes/pkg/cluster"
)

func main() {
	if err := run(); err != nil {
		log.Fatal(err)
	}
}
func run() error {
	config := flag.String("kubeconfig", "", "dedicated nested kubeconfig")
	ns := flag.String("namespace", "lab-watch-scale", "lab namespace")
	endpoint := flag.String("server", "https://127.0.0.1:19447", "trusted port-forward")
	ca := flag.String("ca", "/work/tls/watch/tls.crt", "gateway CA")
	flag.Parse()
	c, err := cluster.New(*config, "admin@workshop")
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Minute)
	defer cancel()
	if err := c.Guard(ctx); err != nil {
		return err
	}
	tlsConfig, err := rest.TLSConfigFor(c.Config)
	if err != nil {
		return err
	}
	data, err := os.ReadFile(*ca)
	if err != nil {
		return err
	}
	tlsConfig.RootCAs = x509.NewCertPool()
	if !tlsConfig.RootCAs.AppendCertsFromPEM(data) {
		return fmt.Errorf("empty gateway CA")
	}
	tlsConfig.ServerName = ""
	transport := &http.Transport{TLSClientConfig: tlsConfig, ForceAttemptHTTP2: true, MaxIdleConnsPerHost: 128}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	query := url.Values{"watch": {"true"}, "fieldSelector": {"metadata.name=kube-root-ca.crt"}, "resourceVersion": {"0"}, "timeoutSeconds": {"1800"}}
	path := *endpoint + "/api/v1/namespaces/" + *ns + "/configmaps?" + query.Encode()
	open := func() (*http.Response, error) {
		r, err := http.NewRequestWithContext(ctx, "GET", path, nil)
		if err != nil {
			return nil, err
		}
		return client.Do(r)
	}
	bodies := []io.ReadCloser{}
	var mu sync.Mutex
	defer func() {
		for _, body := range bodies {
			_ = body.Close()
		}
	}()
	var next, ready atomic.Int64
	var workers sync.WaitGroup
	errors := make(chan error, 100)
	for i := 0; i < 100; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for next.Add(1) <= 10000 {
				response, err := open()
				if err != nil {
					errors <- err
					return
				}
				if response.StatusCode != 200 {
					b, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
					_ = response.Body.Close()
					errors <- fmt.Errorf("watch before threshold returned %d: %s", response.StatusCode, b)
					return
				}
				var event struct{ Type string }
				if err := json.NewDecoder(response.Body).Decode(&event); err != nil || event.Type != "ADDED" {
					_ = response.Body.Close()
					errors <- fmt.Errorf("initial watch event %q: %v", event.Type, err)
					return
				}
				mu.Lock()
				bodies = append(bodies, response.Body)
				mu.Unlock()
				if n := ready.Add(1); n%1000 == 0 {
					log.Printf("live watches with observed ADDED events=%d", n)
				}
			}
		}()
	}
	workers.Wait()
	close(errors)
	for err := range errors {
		return err
	}
	if ready.Load() != 10000 {
		return fmt.Errorf("only %d watches opened", ready.Load())
	}
	response, err := open()
	if err != nil {
		return err
	}
	body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	_ = response.Body.Close()
	if response.StatusCode != 451 || !strings.Contains(string(body), "UnavailableForLegalReasons") {
		return fmt.Errorf("10001st watch returned %d: %s", response.StatusCode, body)
	}
	registration, err := c.R("bloggerregistrations", *ns).Get(ctx, "kube-root-ca.crt", metav1.GetOptions{})
	if err != nil {
		return err
	}
	if cluster.Int(registration.Object, 0, "status", "observedConcurrentWatches") != 10001 || cluster.Int(registration.Object, 0, "spec", "threshold") != 10000 || cluster.Bool(registration.Object, "spec", "registered") {
		return fmt.Errorf("threshold denial did not persist the measured unregistered audience: %v", registration.Object["status"])
	}
	fmt.Printf("PASS: 10000 live watches received actual ADDED events; watch 10001 returned %d: %s", response.StatusCode, body)
	if err := c.Patch(ctx, "bloggerregistrations", *ns, "kube-root-ca.crt", cluster.Map{"spec": cluster.Map{"registered": true}}); err != nil {
		return err
	}
	response, err = open()
	if err != nil {
		return err
	}
	defer response.Body.Close()
	var event struct{ Type string }
	if response.StatusCode != 200 || json.NewDecoder(response.Body).Decode(&event) != nil || event.Type != "ADDED" {
		return fmt.Errorf("registration did not restore the watch")
	}
	fmt.Println("PASS: registration restored a real watch after the default threshold")
	return nil
}
