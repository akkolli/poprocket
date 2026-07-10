package model

import (
	"crypto/rand"
	"encoding/hex"
	"time"
)

type Event struct {
	EventID        string        `json:"event_id,omitempty"`
	Severity       string        `json:"severity,omitempty"`
	Title          string        `json:"title,omitempty"`
	Body           string        `json:"body,omitempty"`
	Source         string        `json:"source,omitempty"`
	Actions        []EventAction `json:"actions,omitempty"`
	CardIDs        []string      `json:"card_ids,omitempty"`
	TTLSeconds     int           `json:"ttl_seconds,omitempty"`
	CreatedAt      time.Time     `json:"created_at,omitempty"`
	IdempotencyKey string        `json:"idempotency_key,omitempty"`
}

type EventAction struct {
	ID                   string `json:"id"`
	Title                string `json:"title"`
	Kind                 string `json:"kind"`
	Scope                string `json:"scope,omitempty"`
	RequiresConfirmation bool   `json:"requires_confirmation,omitempty"`
}

type PairingPayload struct {
	Version           int       `json:"version"`
	BridgeID          string    `json:"bridge_id"`
	BridgeName        string    `json:"bridge_name"`
	RelayURL          string    `json:"relay_url,omitempty"`
	RelayWebSocketURL string    `json:"relay_websocket_url,omitempty"`
	PairingToken      string    `json:"pairing_token"`
	BridgePublicKey   string    `json:"bridge_public_key"`
	DirectURLs        []string  `json:"direct_urls"`
	ExpiresAt         time.Time `json:"expires_at"`
}

type PairingCompleteRequest struct {
	PairingToken string   `json:"pairing_token"`
	DeviceID     string   `json:"device_id"`
	DeviceName   string   `json:"device_name,omitempty"`
	PublicKey    string   `json:"public_key"`
	APNSToken    string   `json:"apns_token,omitempty"`
	Scopes       []string `json:"scopes,omitempty"`
}

type PairingCompleteResponse struct {
	DeviceID           string   `json:"device_id"`
	Scopes             []string `json:"scopes"`
	PairingAccessToken string   `json:"pairing_access_token,omitempty"`
	RelayAccessToken   string   `json:"relay_access_token,omitempty"`
}

type DeviceRegistration struct {
	ID        string    `json:"device_id"`
	PublicKey string    `json:"public_key"`
	Scopes    []string  `json:"scopes"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type CardSnapshot struct {
	ID                string       `json:"id"`
	Title             string       `json:"title"`
	Kind              string       `json:"kind"`
	Status            string       `json:"status"`
	Value             any          `json:"value,omitempty"`
	Error             string       `json:"error,omitempty"`
	UpdatedAt         time.Time    `json:"updated_at"`
	StaleAfterSeconds int          `json:"stale_after_seconds"`
	Stale             bool         `json:"stale"`
	Actions           []CardAction `json:"actions,omitempty"`
}

type CardAction struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Kind  string `json:"kind"`
}

type WOLTarget struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	MAC         string     `json:"mac"`
	IPAddress   string     `json:"ip_address,omitempty"`
	BroadcastIP string     `json:"broadcast_ip"`
	UDPPort     int        `json:"udp_port"`
	Source      string     `json:"source,omitempty"`
	CreatedAt   *time.Time `json:"created_at,omitempty"`
	UpdatedAt   *time.Time `json:"updated_at,omitempty"`
}

type WOLTargetRequest struct {
	ID          string `json:"id,omitempty"`
	Name        string `json:"name"`
	MAC         string `json:"mac"`
	IPAddress   string `json:"ip_address,omitempty"`
	BroadcastIP string `json:"broadcast_ip,omitempty"`
	SubnetBits  int    `json:"subnet_bits,omitempty"`
	UDPPort     int    `json:"udp_port,omitempty"`
}

type HealthMonitor struct {
	ID              string     `json:"id"`
	Name            string     `json:"name"`
	Kind            string     `json:"kind"`
	Host            string     `json:"host,omitempty"`
	Port            int        `json:"port,omitempty"`
	URL             string     `json:"url,omitempty"`
	TimeoutSeconds  int        `json:"timeout_seconds"`
	Source          string     `json:"source,omitempty"`
	Status          string     `json:"status"`
	ResponseTimeMS  int64      `json:"response_time_ms,omitempty"`
	Message         string     `json:"message,omitempty"`
	CheckedAt       *time.Time `json:"checked_at,omitempty"`
	StatusChangedAt *time.Time `json:"status_changed_at,omitempty"`
	CreatedAt       *time.Time `json:"created_at,omitempty"`
	UpdatedAt       *time.Time `json:"updated_at,omitempty"`
}

type HealthMonitorRequest struct {
	ID             string `json:"id,omitempty"`
	Name           string `json:"name"`
	Kind           string `json:"kind,omitempty"`
	Host           string `json:"host,omitempty"`
	Port           int    `json:"port,omitempty"`
	URL            string `json:"url,omitempty"`
	TimeoutSeconds int    `json:"timeout_seconds,omitempty"`
}

type HealthMonitorState struct {
	ID              string
	Status          string
	CheckedAt       time.Time
	StatusChangedAt time.Time
}

type ActionEnvelope struct {
	ActionRunID    string            `json:"action_run_id"`
	EventID        string            `json:"event_id,omitempty"`
	ActionID       string            `json:"action_id"`
	ActorDeviceID  string            `json:"actor_device_id"`
	IdempotencyKey string            `json:"idempotency_key,omitempty"`
	Confirmed      bool              `json:"confirmed,omitempty"`
	Parameters     map[string]string `json:"parameters,omitempty"`
	CreatedAt      time.Time         `json:"created_at"`
	Signature      string            `json:"signature,omitempty"`
}

type ActionRecord struct {
	ActionRunID    string     `json:"action_run_id"`
	EventID        string     `json:"event_id,omitempty"`
	ActionID       string     `json:"action_id"`
	ActorDeviceID  string     `json:"actor_device_id"`
	IdempotencyKey string     `json:"idempotency_key,omitempty"`
	Status         string     `json:"status"`
	ResultMessage  string     `json:"result_message,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	CompletedAt    *time.Time `json:"completed_at,omitempty"`
}

func (e *Event) Normalize(now time.Time) {
	if e.EventID == "" {
		e.EventID = NewID("evt")
	}
	if e.CreatedAt.IsZero() {
		e.CreatedAt = now.UTC()
	}
	if e.TTLSeconds <= 0 {
		e.TTLSeconds = 900
	}
	if e.Severity == "" {
		e.Severity = "info"
	}
}

func NewID(prefix string) string {
	var buf [12]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(err)
	}
	return prefix + "_" + hex.EncodeToString(buf[:])
}
