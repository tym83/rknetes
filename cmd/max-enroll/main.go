// max-enroll gates real kuberoot JoinTicket issuance before a worker exists.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/util/validation"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
	"rknetes.su/rknetes/pkg/cluster"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
func run() error {
	kube := flag.String("kubeconfig", "", "nested kubeconfig")
	contextName := flag.String("context", "admin@workshop", "nested and node context")
	nodeConfig := flag.String("node-kubeconfig", "", "private node API config")
	nodeServer := flag.String("node-server", "", "explicit control-plane node API URL")
	name := flag.String("node-name", "", "joining worker identity")
	server := flag.String("max-server", "", "lab MAX gateway URL")
	ca := flag.String("max-ca", "", "MAX serving CA file")
	sessionFile := flag.String("session-file", "", "private MAX second-factor session file")
	failure := flag.String("failure-policy", "Closed", "Closed or Open on unavailable MAX; denial always closes")
	output := flag.String("output", "", "new private membership output file")
	flag.Parse()
	if len(validation.IsDNS1123Label(*name)) != 0 || *failure != "Closed" && *failure != "Open" {
		return fmt.Errorf("valid worker node-name and Closed/Open failure policy required")
	}
	path := filepath.Clean(*output)
	if !strings.HasPrefix(path, "/work/kube/") && !strings.HasPrefix(path, "/work/cleanroom/kube/") {
		return fmt.Errorf("membership must remain in the private builder kube directory")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	c, err := cluster.New(*kube, *contextName)
	if err != nil {
		return err
	}
	if err := c.Guard(ctx); err != nil {
		return err
	}
	u, err := url.Parse(*server)
	if err != nil || u.Scheme != "https" || u.User != nil {
		return fmt.Errorf("explicit HTTPS MAX URL required")
	}
	ip, err := netip.ParseAddr(u.Hostname())
	if err != nil || !(ip.IsLoopback() || netip.MustParsePrefix("10.42.0.0/16").Contains(ip)) {
		return fmt.Errorf("MAX must be a local or nested lab endpoint")
	}
	cfg := rest.CopyConfig(c.Config)
	cfg.Host = *server
	cfg.CAData = nil
	cfg.CAFile = *ca
	cfg.Timeout = 5 * time.Second
	cfg.ServerName = "maxlet.rknet-system.svc"
	client, err := rest.HTTPClientFor(cfg)
	if err != nil {
		return err
	}
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	req, err := http.NewRequestWithContext(ctx, "GET", strings.TrimRight(*server, "/")+"/enrollment/"+*name, nil)
	if err != nil {
		return err
	}
	if *sessionFile != "" {
		token, err := os.ReadFile(*sessionFile)
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	}
	response, probeErr := client.Do(req)
	gate := "MAXEnrolled"
	if probeErr != nil {
		gate = "MAXUnavailableFailOpen"
	} else {
		defer response.Body.Close()
		if response.StatusCode >= 500 {
			gate = "MAXUnavailableFailOpen"
		} else if response.StatusCode != 200 {
			return fmt.Errorf("MAX enrollment denied with HTTP%d; no JoinTicket issued", response.StatusCode)
		} else {
			var result struct {
				Enrolled bool   `json:"enrolled"`
				NodeName string `json:"nodeName"`
			}
			if err := json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&result); err != nil || !result.Enrolled || result.NodeName != *name {
				return fmt.Errorf("invalid MAX enrollment response; no JoinTicket issued")
			}
		}
	}
	if gate != "MAXEnrolled" && *failure != "Open" {
		return fmt.Errorf("MAX unavailable; fail-closed, no JoinTicket issued")
	}
	nodeURL, err := url.Parse(*nodeServer)
	if err != nil || nodeURL.Scheme != "https" || nodeURL.Port() != "50000" || nodeURL.User != nil {
		return fmt.Errorf("explicit node API HTTPS:50000 required")
	}
	nodes, err := c.List(ctx, "nodes", "")
	if err != nil {
		return err
	}
	authorized := false
	for _, node := range nodes {
		addresses, ok := node.Object["status"].(map[string]interface{})["addresses"].([]interface{})
		if !ok {
			continue
		}
		for _, item := range addresses {
			address := item.(map[string]interface{})
			authorized = authorized || address["type"] == "InternalIP" && address["address"] == nodeURL.Hostname()
		}
	}
	if !authorized {
		return fmt.Errorf("node API must belong to an existing node of this marked stand")
	}
	nc, err := cluster.New(*nodeConfig, *contextName)
	if err != nil {
		return err
	}
	nc.Config.Host = *nodeServer
	nc.Dynamic, err = dynamic.NewForConfig(nc.Config)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	var random [8]byte
	if _, err := rand.Read(random[:]); err != nil {
		return err
	}
	ticketName := "max-" + hex.EncodeToString(random[:])
	ticket := cluster.NewObject("node.kuberoot.dev/v1alpha1", "JoinTicket", "", ticketName, cluster.Map{"nodeName": *name, "role": "Worker", "ttl": "1m"})
	issued, err := nc.Dynamic.Resource(schema.GroupVersionResource{Group: "node.kuberoot.dev", Version: "v1alpha1", Resource: "jointickets"}).Create(ctx, ticket, metav1.CreateOptions{})
	if err != nil {
		os.Remove(path)
		return err
	}
	membership := cluster.String(issued.Object, "status", "membership")
	if membership == "" {
		return fmt.Errorf("issued ticket has no membership")
	}
	if _, err := io.WriteString(file, membership); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	fmt.Printf("JoinTicket issued: name=%s node=%s gate=%s expires=%s membershipBytes=%d; credentials saved privately\n", ticketName, *name, gate, cluster.String(issued.Object, "status", "expires"), len(membership))
	return nil
}
