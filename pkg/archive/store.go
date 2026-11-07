// Package archive stores bounded packet payloads and independently observed flows.
package archive

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type Store struct {
	mu        sync.Mutex
	Directory string
	Limit     int64
	Retention time.Duration
	bytes     int64
	files     map[string]*os.File
	sizes     map[string]int64
	serial    int64
	Full      bool
}

func Open(directory string, limit int64, retention time.Duration) (*Store, error) {
	if limit < 1<<20 || retention < 180*24*time.Hour {
		return nil, fmt.Errorf("at least1MiB and180days required")
	}
	if err := os.MkdirAll(directory, 0700); err != nil {
		return nil, err
	}
	s := &Store{Directory: directory, Limit: limit, Retention: retention, files: map[string]*os.File{}, sizes: map[string]int64{}}
	if err := s.Prune(time.Now()); err != nil {
		return nil, err
	}
	return s, nil
}
func (s *Store) Prune(now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	entries, err := os.ReadDir(s.Directory)
	if err != nil {
		return err
	}
	s.bytes = 0
	for _, e := range entries {
		if e.Type()&os.ModeSymlink != 0 || e.IsDir() || (!strings.HasSuffix(e.Name(), ".pcap") && !strings.HasSuffix(e.Name(), ".jsonl")) {
			continue
		}
		info, err := e.Info()
		if err != nil {
			return err
		}
		path := filepath.Join(s.Directory, e.Name())
		active := false
		for _, f := range s.files {
			if f.Name() == path {
				active = true
			}
		}
		if !active && now.Sub(info.ModTime()) > s.Retention {
			if err := os.Remove(path); err != nil {
				return err
			}
		} else {
			s.bytes += info.Size()
		}
	}
	return nil
}
func (s *Store) write(kind string, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.bytes+int64(len(data))+24 > s.Limit {
		s.Full = true
		return syscall.ENOSPC
	}
	f := s.files[kind]
	if f == nil || s.sizes[kind] > 4<<20 {
		if f != nil {
			if err := f.Sync(); err != nil {
				s.Full = errors.Is(err, syscall.ENOSPC)
				return err
			}
			f.Close()
		}
		s.serial++
		path := filepath.Join(s.Directory, fmt.Sprintf("%d-%d.%s", time.Now().UnixNano(), s.serial, kind))
		var err error
		f, err = os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			s.Full = errors.Is(err, syscall.ENOSPC)
			return err
		}
		s.files[kind] = f
		s.sizes[kind] = 0
		if kind == "pcap" {
			header := make([]byte, 24)
			binary.LittleEndian.PutUint32(header, 0xa1b2c3d4)
			binary.LittleEndian.PutUint16(header[4:], 2)
			binary.LittleEndian.PutUint16(header[6:], 4)
			binary.LittleEndian.PutUint32(header[16:], 65535)
			binary.LittleEndian.PutUint32(header[20:], 1)
			n, err := f.Write(header)
			s.bytes += int64(n)
			s.sizes[kind] += int64(n)
			if err != nil {
				return err
			}
		}
	}
	previous := s.sizes[kind]
	n, err := f.Write(data)
	s.bytes += int64(n)
	s.sizes[kind] += int64(n)
	if err == nil && previous/(1<<20) != s.sizes[kind]/(1<<20) {
		err = f.Sync()
	}
	s.Full = errors.Is(err, syscall.ENOSPC)
	return err
}
func (s *Store) Packet(packet []byte) error {
	now := time.Now()
	data := make([]byte, 16+len(packet))
	binary.LittleEndian.PutUint32(data, uint32(now.Unix()))
	binary.LittleEndian.PutUint32(data[4:], uint32(now.Nanosecond()/1000))
	binary.LittleEndian.PutUint32(data[8:], uint32(len(packet)))
	binary.LittleEndian.PutUint32(data[12:], uint32(len(packet)))
	copy(data[16:], packet)
	return s.write("pcap", data)
}
func (s *Store) Flow(data []byte) error { return s.write("jsonl", append(data, '\n')) }
func (s *Store) Stats() (int64, uint64, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var fs syscall.Statfs_t
	syscall.Statfs(s.Directory, &fs)
	return s.bytes, fs.Bavail * uint64(fs.Bsize), s.Full
}
