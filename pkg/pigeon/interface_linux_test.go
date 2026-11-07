package pigeon

import (
	"net/netip"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestPeerBoundary(t *testing.T) {
	source := netip.MustParseAddr("198.18.0.1")
	destination := netip.MustParseAddr("198.18.0.2")
	packet := make([]byte, 20)
	packet[0] = 0x45
	copy(packet[12:16], source.AsSlice())
	copy(packet[16:20], destination.AsSlice())
	if !packetFor(packet, source, destination) {
		t.Fatal("expected benchmark-range peer packet")
	}
	if packetFor(packet, destination, source) || packetFor(packet[:19], source, destination) {
		t.Fatal("accepted a reversed or truncated packet")
	}
	packet[16] = 10
	if packetFor(packet, source, destination) {
		t.Fatal("accepted an out-of-peer destination")
	}
}

func TestConcurrentEndpointsShareOneStorageBudget(t *testing.T) {
	spool := t.TempDir()
	inbox := filepath.Join(spool, "in")
	if err := os.Mkdir(inbox, 0700); err != nil {
		t.Fatal(err)
	}
	seed, err := os.Create(filepath.Join(spool, "previous-evidence"))
	if err != nil {
		t.Fatal(err)
	}
	if err := seed.Truncate((32 << 20) - 4096); err != nil {
		t.Fatal(err)
	}
	if err := seed.Close(); err != nil {
		t.Fatal(err)
	}
	var group sync.WaitGroup
	accepted := make(chan bool, 16)
	errors := make(chan error, 16)
	for range 16 {
		group.Go(func() {
			ok, err := queuePacket(spool, inbox, make([]byte, 1000))
			accepted <- ok
			errors <- err
		})
	}
	group.Wait()
	close(accepted)
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	count := 0
	for ok := range accepted {
		if ok {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("remaining single packet block admitted %d packets, want 1", count)
	}
}
