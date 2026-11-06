package nationaldns

import (
	"golang.org/x/net/dns/dnsmessage"
	"testing"
)

func TestLabZonesRefuseExternalNamesAndAddresses(t *testing.T) {
	query := func(name string) []byte {
		n, err := dnsmessage.NewName(name)
		if err != nil {
			t.Fatal(err)
		}
		packet, err := (&dnsmessage.Message{Header: dnsmessage.Header{ID: 17, RecursionDesired: true}, Questions: []dnsmessage.Question{{Name: n, Type: dnsmessage.TypeA, Class: dnsmessage.ClassINET}}}).Pack()
		if err != nil {
			t.Fatal(err)
		}
		return packet
	}
	data, err := Answer(query("domestic.lab."), Config{Records: map[string]string{"domestic.lab.": "10.42.1.10"}})
	if err != nil {
		t.Fatal(err)
	}
	var message dnsmessage.Message
	if err := message.Unpack(data); err != nil {
		t.Fatal(err)
	}
	if message.ID != 17 || len(message.Answers) != 1 {
		t.Fatal(message)
	}
	data, err = Answer(query("example.com."), Config{Upstream: "8.8.8.8:53"})
	if err != nil {
		t.Fatal(err)
	}
	message.Unpack(data)
	if message.RCode != dnsmessage.RCodeRefused {
		t.Fatal(message.RCode)
	}
	if _, err := Answer(query("missing.lab."), Config{Upstream: "8.8.8.8:53"}); err == nil {
		t.Fatal("external upstream accepted")
	}
	if _, err := Answer(query("domestic.lab."), Config{Records: map[string]string{"domestic.lab.": "10.244.8.11"}}); err == nil {
		t.Fatal("outer address accepted")
	}
}
