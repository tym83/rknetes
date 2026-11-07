package admission

import "testing"

func TestOriginAndRetaggedDigest(t *testing.T) {
	for _, tc := range []struct {
		image   string
		foreign bool
	}{
		{"nginx:1.27", true}, {"library/nginx:1.27", true}, {"docker.io/library/nginx", true},
		{"registry.goshran.svc/otechestvenny@sha256:123", true},
		{"registry.goshran.svc/native@sha256:456", false}, {"docker.io.evil.example/native", false},
	} {
		if got := IsForeign(tc.image, []string{"sha256:123"}); got != tc.foreign {
			t.Errorf("origin(%q)=%v, want %v", tc.image, got, tc.foreign)
		}
	}
}
