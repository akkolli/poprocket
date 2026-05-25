package wol

import (
	"context"
	"fmt"
	"net"
	"strconv"
)

func MagicPacket(mac net.HardwareAddr) ([]byte, error) {
	if len(mac) != 6 {
		return nil, fmt.Errorf("mac must be 6 bytes, got %d", len(mac))
	}
	packet := make([]byte, 6+16*len(mac))
	for i := 0; i < 6; i++ {
		packet[i] = 0xff
	}
	offset := 6
	for i := 0; i < 16; i++ {
		copy(packet[offset:offset+len(mac)], mac)
		offset += len(mac)
	}
	return packet, nil
}

func Send(ctx context.Context, macAddress, broadcastIP string, port int) error {
	mac, err := net.ParseMAC(macAddress)
	if err != nil {
		return err
	}
	packet, err := MagicPacket(mac)
	if err != nil {
		return err
	}
	if port == 0 {
		port = 9
	}
	addr := net.JoinHostPort(broadcastIP, strconv.Itoa(port))
	dialer := &net.Dialer{}
	conn, err := dialer.DialContext(ctx, "udp4", addr)
	if err != nil {
		return err
	}
	defer conn.Close()
	_, err = conn.Write(packet)
	return err
}
