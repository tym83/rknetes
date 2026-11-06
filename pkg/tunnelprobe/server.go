package tunnelprobe

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

type Route struct {
	URL       string `json:"url"`
	Proxy     string `json:"proxy,omitempty"`
	Interface string `json:"interface,omitempty"`
}

type Server struct{ Config string }

func (s Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/healthz" {
		fmt.Fprint(w, "ok")
		return
	}
	if r.URL.Path != "/probe" || r.Method != "GET" {
		http.NotFound(w, r)
		return
	}
	var routes map[string]Route
	data, err := os.ReadFile(s.Config)
	if err == nil {
		err = json.Unmarshal(data, &routes)
	}
	route, found := routes[r.URL.Query().Get("protocol")]
	if err != nil || !found {
		http.Error(w, "unknown configured lab protocol", 400)
		return
	}
	args, err := Arguments(route)
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	output, err := exec.CommandContext(r.Context(), "curl", args...).CombinedOutput()
	if len(output) > 4096 {
		output = output[:4096]
	}
	result := map[string]interface{}{"success": err == nil, "bytes": len(output), "protocol": r.URL.Query().Get("protocol")}
	if err != nil {
		result["error"] = strings.TrimSpace(string(output))
	} else {
		digest := sha256.Sum256(output)
		result["sha256"] = hex.EncodeToString(digest[:])
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func Arguments(route Route) ([]string, error) {
	u, err := url.Parse(route.URL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil {
		return nil, fmt.Errorf("an explicit lab HTTP URL is required")
	}
	ip, err := netip.ParseAddr(u.Hostname())
	if err != nil || !(ip.IsLoopback() || netip.MustParsePrefix("10.42.0.0/16").Contains(ip) || netip.MustParsePrefix("198.19.0.0/16").Contains(ip)) {
		return nil, fmt.Errorf("probe target must be a literal nested Pod or benchmark address")
	}
	args := []string{"--fail", "--silent", "--show-error", "--max-time", "3", "--max-filesize", "4096", "--noproxy", "", "--proxy", ""}
	if route.Proxy != "" {
		p, err := url.Parse(route.Proxy)
		if err != nil || p.Scheme != "socks5h" || p.Hostname() != "127.0.0.1" || p.Port() == "" || p.User != nil {
			return nil, fmt.Errorf("only a local SOCKS protocol driver is accepted")
		}
		args = append(args, "--proxy", route.Proxy)
	}
	if route.Interface != "" {
		if !regexp.MustCompile(`^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,14}$`).MatchString(route.Interface) {
			return nil, fmt.Errorf("invalid local tunnel interface")
		}
		args = append(args, "--interface", route.Interface)
	}
	return append(args, route.URL), nil
}
