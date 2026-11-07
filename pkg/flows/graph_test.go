package flows

import (
	"bytes"
	"strings"
	"testing"
)

func TestRootGraphKeepsVerdictsCyclesAndUnknowns(t *testing.T) {
	g := Graph{}
	g.Add("lab/shop", "lab/sms", "FORWARDED")
	g.Add("lab/sms", "lab/captcha", "DROPPED")
	g.Add("lab/captcha", "lab/shop", "FORWARDED")
	g.Add("lab/unrelated", "lab/foreign", "FORWARDED")
	var b bytes.Buffer
	g.Print([]string{"lab/shop", "lab/missing"}, &b)
	for _, want := range []string{"lab/sms", "lab/captcha [DROPPED=1]", "already visited", "lab/missing [NO_OBSERVATION"} {
		if !strings.Contains(b.String(), want) {
			t.Fatalf("missing %q: %s", want, b.String())
		}
	}
	if strings.Contains(b.String(), "lab/unrelated") {
		t.Fatal("unrelated traffic entered root graph")
	}
}
