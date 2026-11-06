package pigeon

import (
	"context"
	"fmt"
	"golang.org/x/sys/unix"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// Endpoint joins a real TUN interface to the existing file courier. Addresses
// are restricted to the two benchmark-range peers; no default route is added.
func Endpoint(ctx context.Context, spool, source, destination, address, peer string, delay time.Duration, loss int) error {
	for _, name := range []string{source, destination} {
		if name == "" || filepath.Base(name) != name || strings.Contains(name, "..") {
			return fmt.Errorf("invalid namespace name")
		}
	}
	local, err := netip.ParsePrefix(address)
	if err != nil {
		return err
	}
	remote, err := netip.ParseAddr(peer)
	if err != nil {
		return err
	}
	benchmark := netip.MustParsePrefix("198.18.0.0/16")
	if !local.Addr().Is4() || !benchmark.Contains(local.Addr()) || !benchmark.Contains(remote) || local.Bits() != 30 || !local.Contains(remote) || local.Addr() == remote {
		return fmt.Errorf("two distinct benchmark-range /30 peers required")
	}
	// Attach before registering the descriptor with Go's poller. An unattached
	// TUN reports EPOLLERR and has no packet wait queue yet; registering it at
	// open time can leave subsequent reads asleep despite queued packets.
	fd, err := unix.Open("/dev/net/tun", unix.O_RDWR|unix.O_NONBLOCK|unix.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	request, err := unix.NewIfreq("pigeon0")
	if err != nil {
		unix.Close(fd)
		return err
	}
	request.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if err := unix.IoctlIfreq(fd, unix.TUNSETIFF, request); err != nil {
		unix.Close(fd)
		return err
	}
	f := os.NewFile(uintptr(fd), "/dev/net/tun")
	defer f.Close()
	for _, args := range [][]string{{"address", "add", address, "dev", "pigeon0"}, {"link", "set", "dev", "pigeon0", "mtu", "1200", "up"}} {
		if out, err := exec.CommandContext(ctx, "ip", args...).CombinedOutput(); err != nil {
			return fmt.Errorf("configure lab TUN: %v: %s", err, out)
		}
	}
	inbox := filepath.Join(spool, "in", destination)
	outbox := filepath.Join(spool, "out", source)
	consumed := filepath.Join(spool, "consumed", source)
	for _, d := range []string{inbox, outbox, consumed} {
		if err := os.MkdirAll(d, 0700); err != nil {
			return err
		}
	}
	child, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make(chan error, 3)
	go func() { results <- Run(child, spool, destination, delay, loss) }()
	go func() {
		buffer := make([]byte, 65535)
		lastFullReport := time.Time{}
		for {
			n, err := f.Read(buffer)
			if err != nil {
				results <- err
				return
			}
			if !packetFor(buffer[:n], local.Addr(), remote) {
				continue
			}
			accepted, err := queuePacket(spool, inbox, buffer[:n])
			if err != nil {
				results <- err
				return
			}
			if !accepted && time.Since(lastFullReport) >= time.Second {
				fmt.Println("packet rejected: bounded avian storage full")
				lastFullReport = time.Now()
			}
		}
	}()
	go func() {
		tick := time.NewTicker(100 * time.Millisecond)
		defer tick.Stop()
		for {
			entries, err := os.ReadDir(outbox)
			if err != nil {
				results <- err
				return
			}
			for _, entry := range entries {
				if !entry.Type().IsRegular() || strings.HasPrefix(entry.Name(), ".") {
					continue
				}
				path := filepath.Join(outbox, entry.Name())
				info, err := entry.Info()
				if err != nil {
					results <- err
					return
				}
				if info.Size() > 65535 {
					results <- fmt.Errorf("oversized carrier packet")
					return
				}
				packet, err := os.ReadFile(path)
				if err != nil {
					results <- err
					return
				}
				if !packetFor(packet, remote, local.Addr()) {
					results <- fmt.Errorf("carrier packet outside the two lab peers")
					return
				}
				if _, err := f.Write(packet); err != nil {
					results <- err
					return
				}
				if err := os.Rename(path, filepath.Join(consumed, entry.Name())); err != nil {
					results <- err
					return
				}
			}
			select {
			case <-child.Done():
				results <- nil
				return
			case <-tick.C:
			}
		}
	}()
	fmt.Printf("avian TUN ready: %s -> %s; delay=%s loss=%d%%\n", address, peer, delay, loss)
	select {
	case <-ctx.Done():
		return nil
	case err := <-results:
		return err
	}
}

// Both endpoints share this lock. Count allocated blocks and files, including
// delivered/lost evidence, so tiny packets cannot exhaust the node's inodes.
func queuePacket(spool, inbox string, packet []byte) (bool, error) {
	lock, err := os.OpenFile(filepath.Join(spool, ".quota.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return false, err
	}
	defer lock.Close()
	if err := unix.Flock(int(lock.Fd()), unix.LOCK_EX); err != nil {
		return false, err
	}
	defer unix.Flock(int(lock.Fd()), unix.LOCK_UN)
	var allocated int64
	files := 0
	err = filepath.WalkDir(spool, func(path string, d os.DirEntry, err error) error {
		if os.IsNotExist(err) {
			return nil
		}
		if err != nil {
			return err
		}
		if d.Type().IsRegular() {
			info, err := d.Info()
			if os.IsNotExist(err) {
				return nil
			}
			if err != nil {
				return err
			}
			files++
			allocated += max(info.Size(), info.Sys().(*syscall.Stat_t).Blocks*512)
		}
		return nil
	})
	if err != nil {
		return false, err
	}
	if files >= 8192 || allocated+int64((len(packet)+4095)/4096*4096) > 32<<20 {
		return false, nil
	}
	temp, err := os.CreateTemp(inbox, ".flight-")
	if err != nil {
		return false, err
	}
	name := temp.Name()
	defer os.Remove(name)
	_, writeErr := temp.Write(packet)
	closeErr := temp.Close()
	if writeErr != nil || closeErr != nil {
		return false, fmt.Errorf("queue packet: %v %v", writeErr, closeErr)
	}
	err = os.Rename(name, filepath.Join(inbox, strings.TrimPrefix(filepath.Base(name), ".")))
	return err == nil, err
}

func packetFor(packet []byte, source, destination netip.Addr) bool {
	if len(packet) < 20 || packet[0]>>4 != 4 {
		return false
	}
	src := netip.AddrFrom4([4]byte(packet[12:16]))
	dst := netip.AddrFrom4([4]byte(packet[16:20]))
	return src == source && dst == destination
}
