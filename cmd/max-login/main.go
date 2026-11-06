package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/term"
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
	kube := flag.String("kubeconfig", "", "private kubeconfig")
	contextName := flag.String("context", "admin@workshop", "context")
	server := flag.String("server", os.Getenv("HODATAY_MAX_SERVER"), "MAX HTTPS endpoint")
	ca := flag.String("ca", os.Getenv("HODATAY_MAX_CA"), "MAX CA file")
	output := flag.String("output", "", "private session file for HODATAY_MAX_SESSION_FILE")
	flag.Parse()
	if !strings.HasPrefix(*server, "https://") || *ca == "" || *output == "" {
		return fmt.Errorf("HTTPS server, CA and private output are required")
	}
	code := os.Getenv("HODATAY_MAX_CODE")
	if code == "" {
		fmt.Fprint(os.Stderr, "Код подтверждения MAX: ")
		value, err := term.ReadPassword(int(os.Stdin.Fd()))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			return err
		}
		code = string(value)
	}
	c, err := cluster.New(*kube, *contextName)
	if err != nil {
		return err
	}
	cfg := rest.CopyConfig(c.Config)
	cfg.Host = *server
	cfg.CAData = nil
	cfg.CAFile = *ca
	cfg.Timeout = 10 * time.Second
	cfg.ServerName = "maxlet.rknet-system.svc"
	client, err := rest.HTTPClientFor(cfg)
	if err != nil {
		return err
	}
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	body, _ := json.Marshal(map[string]string{"code": strings.TrimSpace(code)})
	response, err := client.Post(strings.TrimRight(*server, "/")+"/session", "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("MAX second factor rejected: HTTP%d", response.StatusCode)
	}
	var result struct {
		Token   string `json:"token"`
		Expires string `json:"expires"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&result); err != nil {
		return err
	}
	if len(result.Token) != 64 {
		return fmt.Errorf("invalid MAX session response")
	}
	file, err := os.CreateTemp(filepath.Dir(*output), ".max-session-")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := io.WriteString(file, result.Token); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Rename(file.Name(), *output); err != nil {
		return err
	}
	fmt.Printf("MAX: второй фактор принят; сессия действует до %s\n", result.Expires)
	return nil
}
