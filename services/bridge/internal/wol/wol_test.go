package wol

import (
	"bytes"
	"net"
	"testing"
)

func TestMagicPacket(t *testing.T) {
	mac := net.HardwareAddr{0x02, 0x00, 0x5e, 0x10, 0x00, 0x01}
	packet, err := MagicPacket(mac)
	if err != nil {
		t.Fatalf("MagicPacket() error = %v", err)
	}
	if got, want := len(packet), 102; got != want {
		t.Fatalf("len(packet) = %d, want %d", got, want)
	}
	if !bytes.Equal(packet[:6], []byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff}) {
		t.Fatalf("packet prefix = %x", packet[:6])
	}
	for offset := 6; offset < len(packet); offset += 6 {
		if !bytes.Equal(packet[offset:offset+6], mac) {
			t.Fatalf("mac repeat at %d = %x", offset, packet[offset:offset+6])
		}
	}
}

func TestMagicPacketRejectsBadMAC(t *testing.T) {
	_, err := MagicPacket(net.HardwareAddr{1, 2, 3})
	if err == nil {
		t.Fatal("expected bad mac error")
	}
}
