package tspu

import (
	"rknetes.su/rknetes/pkg/cluster"
	"testing"
)

func TestRejectsHostAndExternalRanges(t *testing.T) {
	for _, cidr := range []string{"0.0.0.0/0", "10.244.8.0/24", "10.42.0.0/15", "10.96.0.1/32", "::/0", "garbage"} {
		_, err := ParseSettings(cluster.Map{"spec": cluster.Map{"foreignCIDRs": []interface{}{cidr}}})
		if err == nil {
			t.Fatalf("accepted out-of-lab CIDR %s", cidr)
		}
	}
	s, err := ParseSettings(cluster.Map{"spec": cluster.Map{"foreignCIDRs": []interface{}{"10.42.1.2/32"}}})
	if err != nil || s.Limit != 16384 || s.Ranges[0].Network != 0x0a2a0102 || s.Ranges[0].Mask != 0xffffffff {
		t.Fatalf("valid lab settings: %+v %v", s, err)
	}
}
