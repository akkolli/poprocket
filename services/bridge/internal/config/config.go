package config

import (
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Bridge        BridgeConfig        `yaml:"bridge"`
	Relay         RelayConfig         `yaml:"relay"`
	Security      SecurityConfig      `yaml:"security"`
	CommandRunner CommandRunnerConfig `yaml:"command_runner"`
	Monitors      []MonitorConfig     `yaml:"monitors"`
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
	PairingTTLSeconds  int      `yaml:"pairing_ttl_seconds"`
	PairingAccessToken string   `yaml:"pairing_access_token"`
	NotificationToken  string   `yaml:"notification_token"`
	DefaultScopes      []string `yaml:"default_scopes"`
}

type CommandRunnerConfig struct {
	Enabled             bool     `yaml:"enabled"`
	AllowAdHoc          bool     `yaml:"allow_ad_hoc"`
	AllowShellOperators bool     `yaml:"allow_shell_operators"`
	Shell               string   `yaml:"shell"`
	TimeoutSeconds      int      `yaml:"timeout_seconds"`
	MaxOutputBytes      int      `yaml:"max_output_bytes"`
	AllowedPrefixes     []string `yaml:"allowed_prefixes"`
}

type WOLTarget struct {
	ID          string   `yaml:"id"`
	Name        string   `yaml:"name"`
	MAC         string   `yaml:"mac"`
	IPAddress   string   `yaml:"ip_address"`
	BroadcastIP string   `yaml:"broadcast_ip"`
	UDPPort     int      `yaml:"udp_port"`
	Scopes      []string `yaml:"scopes"`
}

type MonitorConfig struct {
	ID             string `yaml:"id"`
	Name           string `yaml:"name"`
	Kind           string `yaml:"kind"`
	Host           string `yaml:"host"`
	Port           int    `yaml:"port"`
	URL            string `yaml:"url"`
	TimeoutSeconds int    `yaml:"timeout_seconds"`
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
	c.Bridge.Name = normalizeBridgeName(c.Bridge.Name)
	if c.Bridge.DataPath == "" {
		c.Bridge.DataPath = "/var/lib/poprocket/poprocket.db"
	}
	if c.Relay.URL != "" {
		parsed, err := url.ParseRequestURI(c.Relay.URL)
		if err != nil {
			return fmt.Errorf("relay.url: %w", err)
		}
		if parsed.Scheme != "http" && parsed.Scheme != "https" {
			return errors.New("relay.url must use http or https")
		}
	}
	if c.Relay.WebSocketURL != "" {
		parsed, err := url.ParseRequestURI(c.Relay.WebSocketURL)
		if err != nil {
			return fmt.Errorf("relay.websocket_url: %w", err)
		}
		if parsed.Scheme != "ws" && parsed.Scheme != "wss" {
			return errors.New("relay.websocket_url must use ws or wss")
		}
	}
	if (c.Relay.URL != "" || c.Relay.WebSocketURL != "") && strings.TrimSpace(c.Relay.Token) == "" {
		return errors.New("relay.token is required when relay URLs are configured")
	}
	if c.Security.PairingTTLSeconds <= 0 {
		c.Security.PairingTTLSeconds = 300
	}
	if c.Security.PairingTTLSeconds > 900 {
		return errors.New("security.pairing_ttl_seconds must not exceed 900")
	}
	if token := strings.TrimSpace(c.Security.PairingAccessToken); token != "" && len(token) < 16 {
		return errors.New("security.pairing_access_token must be at least 16 characters")
	}
	if token := strings.TrimSpace(c.Security.NotificationToken); token != "" && len(token) < 16 {
		return errors.New("security.notification_token must be at least 16 characters")
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
	if c.CommandRunner.TimeoutSeconds > 300 {
		return errors.New("command_runner.timeout_seconds must not exceed 300")
	}
	if c.CommandRunner.MaxOutputBytes > 1<<20 {
		return errors.New("command_runner.max_output_bytes must not exceed 1048576")
	}
	prefixes := c.CommandRunner.AllowedPrefixes[:0]
	for _, prefix := range c.CommandRunner.AllowedPrefixes {
		if prefix = strings.TrimSpace(prefix); prefix != "" {
			prefixes = append(prefixes, prefix)
		}
	}
	c.CommandRunner.AllowedPrefixes = prefixes
	if c.CommandRunner.Enabled && c.CommandRunner.AllowAdHoc && len(c.CommandRunner.AllowedPrefixes) == 0 {
		return errors.New("command_runner.allowed_prefixes must not be empty when ad-hoc commands are enabled")
	}

	ids := map[string]string{}
	for i := range c.Monitors {
		monitor := &c.Monitors[i]
		if err := normalizeMonitorConfig(monitor); err != nil {
			return err
		}
		if prev := ids["monitor:"+monitor.ID]; prev != "" {
			return fmt.Errorf("duplicate monitor id %q previously defined as %s", monitor.ID, prev)
		}
		ids["monitor:"+monitor.ID] = monitor.Name
	}
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
		if target.IPAddress != "" {
			ip := net.ParseIP(target.IPAddress)
			if ip == nil || ip.To4() == nil {
				return fmt.Errorf("wol target %s ip_address is invalid", target.ID)
			}
			target.IPAddress = ip.To4().String()
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

func normalizeBridgeName(name string) string {
	switch strings.TrimSpace(name) {
	case "", "PopRocket Pi Bridge", "PopRocket Bridge":
		return "Local Bridge"
	default:
		return strings.TrimSpace(name)
	}
}

func normalizeMonitorConfig(monitor *MonitorConfig) error {
	if monitor.ID == "" {
		return errors.New("monitor id is required")
	}
	if monitor.Name == "" {
		monitor.Name = monitor.ID
	}
	if monitor.Kind == "" {
		if monitor.URL != "" {
			monitor.Kind = "http"
		} else {
			monitor.Kind = "tcp"
		}
	}
	switch monitor.Kind {
	case "tcp":
		if monitor.Host == "" {
			return fmt.Errorf("monitor %s host is required", monitor.ID)
		}
		if monitor.Port == 0 {
			monitor.Port = 22
		}
		if monitor.Port < 1 || monitor.Port > 65535 {
			return fmt.Errorf("monitor %s port must be between 1 and 65535", monitor.ID)
		}
	case "http":
		if monitor.URL == "" {
			return fmt.Errorf("monitor %s url is required", monitor.ID)
		}
		if _, err := url.ParseRequestURI(monitor.URL); err != nil {
			return fmt.Errorf("monitor %s url: %w", monitor.ID, err)
		}
	default:
		return fmt.Errorf("monitor %s kind must be tcp or http", monitor.ID)
	}
	if monitor.TimeoutSeconds <= 0 {
		monitor.TimeoutSeconds = 3
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
