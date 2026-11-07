package tspu

import (
	"encoding/binary"
	"fmt"
	"github.com/cilium/ebpf"
	"rknetes.su/rknetes/pkg/cluster"
)

// KernelCheck executes the actual loaded tc program on constructed packets. It
// needs BPF privileges but attaches to no network interface.
func KernelCheck(object string) error {
	spec, err := ebpf.LoadCollectionSpec(object)
	if err != nil {
		return err
	}
	c, err := ebpf.NewCollection(spec)
	if err != nil {
		return err
	}
	defer c.Close()
	settings, err := ParseSettings(cluster.Map{"spec": cluster.Map{"foreignCIDRs": []interface{}{"10.42.0.0/16"}}})
	if err != nil {
		return err
	}
	if err := c.Maps["config"].Update(uint32(0), settings, ebpf.UpdateAny); err != nil {
		return err
	}
	packet := func(port uint16, seq uint32, payload int, syn bool) []byte {
		b := make([]byte, 14+20+20+payload)
		binary.BigEndian.PutUint16(b[12:], 0x0800)
		b[14] = 0x45
		binary.BigEndian.PutUint16(b[16:], uint16(40+payload))
		b[22] = 64
		b[23] = 6
		copy(b[26:30], []byte{10, 42, 0, 1})
		copy(b[30:34], []byte{10, 42, 0, 2})
		binary.BigEndian.PutUint16(b[34:], port)
		binary.BigEndian.PutUint16(b[36:], 8081)
		binary.BigEndian.PutUint32(b[38:], seq)
		b[46] = 0x50
		b[47] = 0x10
		if syn {
			b[47] = 2
		}
		return b
	}
	base := uint32(0xfffffff0)
	tests := []struct {
		name string
		data []byte
		want uint32
	}{
		{"wrapped SYN", packet(30000, base-1, 0, true), 0},
		{"first data", packet(30000, base, 1000, false), 0},
		{"retransmission", packet(30000, base, 1000, false), 0},
		{"wrapped sequence", packet(30000, base+1000, 1000, false), 0},
		{"boundary crossing", packet(30000, base+16000, 1000, false), 2},
		{"exact boundary", packet(30000, base+15384, 1000, false), 0},
		{"over limit", packet(30000, base+16384, 1, false), 2},
		{"ACK remains live", packet(30000, base+16384, 0, false), 0},
		{"independent flow", packet(30001, 42, 1000, false), 0},
	}
	for _, test := range tests {
		got, _, err := c.Programs["sovereign_window"].Test(test.data)
		if err != nil || got != test.want {
			return fmt.Errorf("%s: verdict=%d expected=%d error=%v", test.name, got, test.want, err)
		}
		fmt.Printf("PASS kernel packet: %s verdict=%d\n", test.name, got)
	}
	return nil
}
