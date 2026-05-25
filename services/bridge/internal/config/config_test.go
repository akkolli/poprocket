package config

import (
	"strings"
	"testing"
)

func TestLoadAppliesDefaultsAndValidates(t *testing.T) {
	cfg, err := Load(strings.NewReader(`
bridge:
  id: dev
relay:
  url: http://localhost:8081
security: {}
wol_targets:
  - id: nas
    name: NAS
    mac: 02:00:5e:10:00:01
    broadcast_ip: 192.168.1.255
cards:
  - id: bridge_host
    title: Bridge Host
    kind: host_status
actions:
  - id: wake_nas
    title: Wake NAS
    kind: wol
    target_id: nas
    scopes: ["wol:wake:nas"]
`))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Bridge.Name != "dev" {
		t.Fatalf("bridge name default = %q", cfg.Bridge.Name)
	}
	if cfg.Security.PairingTTLSeconds != 300 {
		t.Fatalf("pairing ttl = %d", cfg.Security.PairingTTLSeconds)
	}
	if cfg.WOLTargets[0].UDPPort != 9 {
		t.Fatalf("wol udp default = %d", cfg.WOLTargets[0].UDPPort)
	}
}

func TestLoadRejectsInvalidMAC(t *testing.T) {
	_, err := Load(strings.NewReader(`
bridge:
  id: dev
wol_targets:
  - id: nas
    mac: nope
    broadcast_ip: 192.168.1.255
`))
	if err == nil {
		t.Fatal("expected invalid mac error")
	}
}
