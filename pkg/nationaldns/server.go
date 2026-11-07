// Package nationaldns implements an isolated lab resolver and reference clock.
package nationaldns

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"strings"
	"time"

	"golang.org/x/net/dns/dnsmessage"
)

type Config struct {
	Records  map[string]string `json:"records"`
	Upstream string            `json:"upstream"`
}

func LabAddress(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip, err := netip.ParseAddr(host)
	if err != nil || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
		return fmt.Errorf("only a literal nested lab endpoint is accepted")
	}
	return nil
}
func Answer(packet []byte, config Config) ([]byte, error) {
	var request dnsmessage.Message
	if err := request.Unpack(packet); err != nil {
		return nil, err
	}
	response := dnsmessage.Message{Header: dnsmessage.Header{ID: request.ID, Response: true, Authoritative: true, RecursionDesired: request.RecursionDesired, RecursionAvailable: true}, Questions: request.Questions}
	if len(request.Questions) != 1 {
		response.RCode = dnsmessage.RCodeFormatError
		return response.Pack()
	}
	q := request.Questions[0]
	name := strings.ToLower(q.Name.String())
	if !strings.HasSuffix(name, ".lab.") {
		response.RCode = dnsmessage.RCodeRefused
		return response.Pack()
	}
	if address, found := config.Records[name]; found {
		ip, err := netip.ParseAddr(address)
		if err != nil || !ip.Is4() || !netip.MustParsePrefix("10.42.0.0/16").Contains(ip) {
			return nil, fmt.Errorf("DNS record must name a nested lab Pod")
		}
		if q.Type == dnsmessage.TypeA {
			response.Answers = []dnsmessage.Resource{{Header: dnsmessage.ResourceHeader{Name: q.Name, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET, TTL: 1}, Body: &dnsmessage.AResource{A: ip.As4()}}}
		}
		return response.Pack()
	}
	if config.Upstream == "" {
		response.RCode = dnsmessage.RCodeNameError
		return response.Pack()
	}
	if err := LabAddress(config.Upstream); err != nil {
		return nil, err
	}
	connection, err := net.DialTimeout("udp", config.Upstream, time.Second)
	if err == nil {
		defer connection.Close()
		connection.SetDeadline(time.Now().Add(time.Second))
		_, err = connection.Write(packet)
		if err == nil {
			buffer := make([]byte, 65535)
			n, readErr := connection.Read(buffer)
			var reply dnsmessage.Message
			if readErr == nil && reply.Unpack(buffer[:n]) == nil && reply.ID == request.ID && reply.Response {
				return buffer[:n], nil
			}
		}
	}
	response.RCode = dnsmessage.RCodeServerFailure
	return response.Pack()
}

func ServeDNS(address, filename string) error {
	answer := func(data []byte) ([]byte, error) {
		var config Config
		body, err := os.ReadFile(filename)
		if err != nil {
			return nil, err
		}
		if err := json.Unmarshal(body, &config); err != nil {
			return nil, err
		}
		return Answer(data, config)
	}
	udp, err := net.ListenPacket("udp", address)
	if err != nil {
		return err
	}
	defer udp.Close()
	tcp, err := net.Listen("tcp", address)
	if err != nil {
		return err
	}
	defer tcp.Close()
	limit := make(chan struct{}, 64)
	go func() {
		for {
			connection, err := tcp.Accept()
			if err != nil {
				return
			}
			go func() {
				defer connection.Close()
				connection.SetDeadline(time.Now().Add(3 * time.Second))
				var size [2]byte
				if _, err := io.ReadFull(connection, size[:]); err != nil {
					return
				}
				data := make([]byte, binary.BigEndian.Uint16(size[:]))
				if _, err := io.ReadFull(connection, data); err != nil {
					return
				}
				reply, err := answer(data)
				if err != nil {
					return
				}
				binary.BigEndian.PutUint16(size[:], uint16(len(reply)))
				connection.Write(size[:])
				connection.Write(reply)
			}()
		}
	}()
	for {
		buffer := make([]byte, 65535)
		n, peer, err := udp.ReadFrom(buffer)
		if err != nil {
			return err
		}
		select {
		case limit <- struct{}{}:
			go func() {
				defer func() { <-limit }()
				reply, err := answer(buffer[:n])
				if err == nil {
					udp.WriteTo(reply, peer)
				}
			}()
		default:
		}
	}
}

const epochOffset = 2208988800

func timestamp(now time.Time) uint64 {
	return uint64(now.Unix()+epochOffset)<<32 | uint64(now.Nanosecond())*(1<<32)/1e9
}
func ServeNTP(address string) error {
	connection, err := net.ListenPacket("udp", address)
	if err != nil {
		return err
	}
	defer connection.Close()
	for {
		var request [512]byte
		n, peer, err := connection.ReadFrom(request[:])
		if err != nil {
			return err
		}
		if n < 48 || request[0]&7 != 3 {
			continue
		}
		var response [48]byte
		response[0] = 0x24
		response[1] = 1
		response[2] = 6
		response[3] = 236
		copy(response[12:16], "RKN!")
		copy(response[24:32], request[40:48])
		now := timestamp(time.Now().UTC())
		binary.BigEndian.PutUint64(response[16:24], now)
		binary.BigEndian.PutUint64(response[32:40], now)
		binary.BigEndian.PutUint64(response[40:48], now)
		connection.WriteTo(response[:], peer)
	}
}
func Clock(address string) (time.Time, error) {
	if err := LabAddress(address); err != nil {
		return time.Time{}, err
	}
	connection, err := net.DialTimeout("udp", address, time.Second)
	if err != nil {
		return time.Time{}, err
	}
	defer connection.Close()
	connection.SetDeadline(time.Now().Add(2 * time.Second))
	var request, response [48]byte
	request[0] = 0x23
	nonce := timestamp(time.Now())
	binary.BigEndian.PutUint64(request[40:48], nonce)
	if _, err := connection.Write(request[:]); err != nil {
		return time.Time{}, err
	}
	if _, err := io.ReadFull(connection, response[:]); err != nil {
		return time.Time{}, err
	}
	if response[0]&7 != 4 || response[1] == 0 || binary.BigEndian.Uint64(response[24:32]) != nonce {
		return time.Time{}, fmt.Errorf("invalid lab NTP response")
	}
	value := binary.BigEndian.Uint64(response[40:48])
	return time.Unix(int64(value>>32)-epochOffset, int64(value&0xffffffff)*1e9/(1<<32)), nil
}
