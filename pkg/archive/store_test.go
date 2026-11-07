package archive

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRetentionAndPacketBoundary(t *testing.T) {
	dir := t.TempDir()
	old := filepath.Join(dir, "expired.pcap")
	os.WriteFile(old, []byte("expired"), 0600)
	past := time.Now().Add(-181 * 24 * time.Hour)
	os.Chtimes(old, past, past)
	recent := filepath.Join(dir, "recent.pcap")
	os.WriteFile(recent, []byte("retained"), 0600)
	s, err := Open(dir, 1<<20, 180*24*time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatal("expired file remains")
	}
	if _, err := os.Stat(recent); err != nil {
		t.Fatal(err)
	}
	packet := bytes.Repeat([]byte{42}, 100)
	if err := s.Packet(packet); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(dir, "*.pcap"))
	for _, path := range files {
		if path == recent {
			continue
		}
		data, _ := os.ReadFile(path)
		if binary.LittleEndian.Uint32(data) != 0xa1b2c3d4 || !bytes.Equal(data[40:], packet) {
			t.Fatal("invalid pcap bytes")
		}
	}
	if _, err := Open(t.TempDir(), 1<<20, 179*24*time.Hour); err == nil {
		t.Fatal("short retention accepted")
	}
}
func TestCaptureExcludesOtherNamespacesAndNonIPv4(t *testing.T) {
	a := Agent{peers: map[string]bool{"10.42.0.1": true, "10.42.0.2": true}}
	packet := make([]byte, 34)
	packet[12] = 8
	packet[14] = 0x45
	copy(packet[26:], []byte{10, 42, 0, 1, 10, 42, 0, 2})
	if !a.allowed(packet) {
		t.Fatal("lab packet excluded")
	}
	packet[33] = 3
	if a.allowed(packet) {
		t.Fatal("unknown peer captured")
	}
	packet[13] = 6
	if a.allowed(packet) {
		t.Fatal("non-IPv4 captured")
	}
}
