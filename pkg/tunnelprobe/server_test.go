package tunnelprobe

import "testing"

func TestRejectsExternalProbeDestinations(t *testing.T) {
	for _, route := range []Route{
		{URL: "https://1.1.1.1"}, {URL: "https://example.com"},
		{URL: "http://10.244.8.11"}, {URL: "http://10.42.0.1", Proxy: "socks5h://10.244.8.11:1080"},
		{URL: "http://10.42.0.1", Interface: "--config"},
	} {
		if _, err := Arguments(route); err == nil {
			t.Fatalf("accepted out-of-scope route: %+v", route)
		}
	}
	if _, err := Arguments(Route{URL: "http://198.19.1.1:8080", Interface: "tun0"}); err != nil {
		t.Fatal(err)
	}
}
