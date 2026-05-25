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
	RelayURL          string    `json:"relay_url"`
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

type ActionEnvelope struct {
	ActionRunID    string    `json:"action_run_id"`
	EventID        string    `json:"event_id,omitempty"`
	ActionID       string    `json:"action_id"`
	ActorDeviceID  string    `json:"actor_device_id"`
	IdempotencyKey string    `json:"idempotency_key,omitempty"`
	Confirmed      bool      `json:"confirmed,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	Signature      string    `json:"signature,omitempty"`
}

type ActionRecord struct {
	ActionRunID   string     `json:"action_run_id"`
	EventID       string     `json:"event_id,omitempty"`
	ActionID      string     `json:"action_id"`
	ActorDeviceID string     `json:"actor_device_id"`
	Status        string     `json:"status"`
	ResultMessage string     `json:"result_message,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
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
