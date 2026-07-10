package config

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestExampleConfigLoads(t *testing.T) {
	path := filepath.Join("..", "..", "..", "..", "configs", "bridge.example.yaml")
	if _, err := LoadFile(path); err != nil {
		t.Fatalf("example config does not load: %v", err)
	}
}

func TestLoadAppliesDefaultsAndValidates(t *testing.T) {
	cfg, err := Load(strings.NewReader(`
bridge:
  id: dev
relay:
  url: http://localhost:8081
  token: test-relay-token
security: {}
monitors:
  - id: ssh
    name: SSH
    host: server
wol_targets:
  - id: target
    name: Target
    mac: 02:00:5e:10:00:01
    broadcast_ip: 192.168.1.255
cards: []
actions:
  - id: wake_target
    title: Wake Target
    kind: wol
    target_id: target
    scopes: ["wol:wake:target"]
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
	if cfg.Monitors[0].Kind != "tcp" || cfg.Monitors[0].Port != 22 || cfg.Monitors[0].TimeoutSeconds != 3 {
		t.Fatalf("monitor defaults = %+v", cfg.Monitors[0])
	}
}

func TestLoadNormalizesLegacyBridgeName(t *testing.T) {
	cfg, err := Load(strings.NewReader(`
bridge:
  id: poprocket-pi
  name: PopRocket Pi Bridge
`))
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Bridge.Name != "Local Bridge" {
		t.Fatalf("bridge name = %q", cfg.Bridge.Name)
	}
}

func TestLoadRejectsInvalidMAC(t *testing.T) {
	_, err := Load(strings.NewReader(`
bridge:
  id: dev
wol_targets:
  - id: target
    mac: nope
    broadcast_ip: 192.168.1.255
`))
	if err == nil {
		t.Fatal("expected invalid mac error")
	}
}

func TestLoadRejectsUnrestrictedAdHocCommands(t *testing.T) {
	_, err := Load(strings.NewReader(`
bridge:
  id: dev
command_runner:
  enabled: true
  allow_ad_hoc: true
  allowed_prefixes: []
`))
	if err == nil || !strings.Contains(err.Error(), "allowed_prefixes") {
		t.Fatalf("error = %v", err)
	}
}
