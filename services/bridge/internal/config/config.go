package config

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Bridge        BridgeConfig        `yaml:"bridge"`
	Relay         RelayConfig         `yaml:"relay"`
	Security      SecurityConfig      `yaml:"security"`
	CommandRunner CommandRunnerConfig `yaml:"command_runner"`
	WOLTargets    []WOLTarget         `yaml:"wol_targets"`
	Cards         []CardConfig        `yaml:"cards"`
	Actions       []ActionConfig      `yaml:"actions"`
}

type BridgeConfig struct {
	ID         string   `yaml:"id"`
	Name       string   `yaml:"name"`
	PublicURL  string   `yaml:"public_url"`
	DirectURLs []string `yaml:"direct_urls"`
	DataPath   string   `yaml:"data_path"`
}

type RelayConfig struct {
	URL          string `yaml:"url"`
	WebSocketURL string `yaml:"websocket_url"`
	Token        string `yaml:"token"`
}

type SecurityConfig struct {
	PairingTTLSeconds int      `yaml:"pairing_ttl_seconds"`
	DefaultScopes     []string `yaml:"default_scopes"`
}

type CommandRunnerConfig struct {
	Enabled         bool     `yaml:"enabled"`
	AllowAdHoc      bool     `yaml:"allow_ad_hoc"`
	Shell           string   `yaml:"shell"`
	TimeoutSeconds  int      `yaml:"timeout_seconds"`
	MaxOutputBytes  int      `yaml:"max_output_bytes"`
	AllowedPrefixes []string `yaml:"allowed_prefixes"`
}

type WOLTarget struct {
	ID          string   `yaml:"id"`
	Name        string   `yaml:"name"`
	MAC         string   `yaml:"mac"`
	BroadcastIP string   `yaml:"broadcast_ip"`
	UDPPort     int      `yaml:"udp_port"`
	Scopes      []string `yaml:"scopes"`
}

type CardConfig struct {
	ID                string        `yaml:"id"`
	Title             string        `yaml:"title"`
	Kind              string        `yaml:"kind"`
	StaleAfterSeconds int           `yaml:"stale_after_seconds"`
	Source            *SourceConfig `yaml:"source"`
}

type SourceConfig struct {
	Method             string            `yaml:"method"`
	URL                string            `yaml:"url"`
	JSONPath           string            `yaml:"json_path"`
	Format             string            `yaml:"format"`
	DockerHost         string            `yaml:"docker_host"`
	Project            string            `yaml:"project"`
	HeadersFromSecrets map[string]string `yaml:"headers_from_secrets"`
}

type ActionConfig struct {
	ID                   string   `yaml:"id"`
	Title                string   `yaml:"title"`
	Kind                 string   `yaml:"kind"`
	TargetID             string   `yaml:"target_id"`
	Operation            string   `yaml:"operation"`
	DockerHost           string   `yaml:"docker_host"`
	Command              string   `yaml:"command"`
	TimeoutSeconds       int      `yaml:"timeout_seconds"`
	RequiresConfirmation bool     `yaml:"requires_confirmation"`
	Scopes               []string `yaml:"scopes"`
}

func LoadFile(path string) (*Config, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	return Load(file)
}

func Load(r io.Reader) (*Config, error) {
	var cfg Config
	dec := yaml.NewDecoder(r)
	dec.KnownFields(true)
	if err := dec.Decode(&cfg); err != nil {
		return nil, err
	}
	if err := cfg.Validate(); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (c *Config) Validate() error {
	if c.Bridge.ID == "" {
		return errors.New("bridge.id is required")
	}
	if c.Bridge.Name == "" {
		c.Bridge.Name = c.Bridge.ID
	}
	if c.Bridge.DataPath == "" {
		c.Bridge.DataPath = "/var/lib/poprocket/poprocket.db"
	}
	if c.Relay.URL != "" {
		if _, err := url.ParseRequestURI(c.Relay.URL); err != nil {
			return fmt.Errorf("relay.url: %w", err)
		}
	}
	if c.Security.PairingTTLSeconds <= 0 {
		c.Security.PairingTTLSeconds = 300
	}
	if c.CommandRunner.Shell == "" {
		c.CommandRunner.Shell = "/bin/sh"
	}
	if c.CommandRunner.TimeoutSeconds <= 0 {
		c.CommandRunner.TimeoutSeconds = 30
	}
	if c.CommandRunner.MaxOutputBytes <= 0 {
		c.CommandRunner.MaxOutputBytes = 4096
	}

	ids := map[string]string{}
	for _, card := range c.Cards {
		if card.ID == "" {
			return errors.New("card id is required")
		}
		if prev := ids["card:"+card.ID]; prev != "" {
			return fmt.Errorf("duplicate card id %q previously defined as %s", card.ID, prev)
		}
		ids["card:"+card.ID] = card.Title
	}
	for i := range c.WOLTargets {
		target := &c.WOLTargets[i]
		if target.ID == "" {
			return errors.New("wol target id is required")
		}
		if target.UDPPort == 0 {
			target.UDPPort = 9
		}
		if _, err := net.ParseMAC(target.MAC); err != nil {
			return fmt.Errorf("wol target %s mac: %w", target.ID, err)
		}
		if net.ParseIP(target.BroadcastIP) == nil {
			return fmt.Errorf("wol target %s broadcast_ip is invalid", target.ID)
		}
		if prev := ids["wol:"+target.ID]; prev != "" {
			return fmt.Errorf("duplicate wol target id %q previously defined as %s", target.ID, prev)
		}
		ids["wol:"+target.ID] = target.Name
	}
	for _, action := range c.Actions {
		if action.ID == "" {
			return errors.New("action id is required")
		}
		if action.Kind == "" {
			return fmt.Errorf("action %s kind is required", action.ID)
		}
		if action.Kind == "command" && action.Command == "" {
			return fmt.Errorf("action %s command is required", action.ID)
		}
		if prev := ids["action:"+action.ID]; prev != "" {
			return fmt.Errorf("duplicate action id %q previously defined as %s", action.ID, prev)
		}
		ids["action:"+action.ID] = action.Title
	}
	return nil
}

func (c Config) FindAction(id string) (ActionConfig, bool) {
	for _, action := range c.Actions {
		if action.ID == id {
			return action, true
		}
	}
	return ActionConfig{}, false
}

func (c Config) FindWOLTarget(id string) (WOLTarget, bool) {
	for _, target := range c.WOLTargets {
		if target.ID == id {
			return target, true
		}
	}
	return WOLTarget{}, false
}
