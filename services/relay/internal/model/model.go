package model

import (
	"encoding/json"
	"time"
)

type DeviceRegistration struct {
	BridgeID  string `json:"bridge_id"`
	DeviceID  string `json:"device_id"`
	Platform  string `json:"platform"`
	APNSToken string `json:"apns_token"`
}

type Device struct {
	BridgeID     string    `json:"bridge_id"`
	DeviceID     string    `json:"device_id"`
	Platform     string    `json:"platform"`
	APNSToken    string    `json:"apns_token"`
	RegisteredAt time.Time `json:"registered_at"`
}

type PushRequest struct {
	BridgeID         string    `json:"bridge_id"`
	EventID          string    `json:"event_id"`
	DeviceIDs        []string  `json:"device_ids,omitempty"`
	EncryptedPayload string    `json:"encrypted_payload"`
	TTLSeconds       int       `json:"ttl_seconds"`
	CreatedAt        time.Time `json:"created_at"`
}

type PushResult struct {
	BridgeID      string `json:"bridge_id"`
	EventID       string `json:"event_id"`
	DeviceCount   int    `json:"device_count"`
	DeliveryCount int    `json:"delivery_count"`
}

type ActionRelayRequest struct {
	BridgeID    string          `json:"bridge_id"`
	ActionRunID string          `json:"action_run_id"`
	DeviceID    string          `json:"device_id"`
	Payload     json.RawMessage `json:"payload"`
	CreatedAt   time.Time       `json:"created_at"`
	TTLSeconds  int             `json:"ttl_seconds"`
}

type BridgeMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

func (r ActionRelayRequest) Expired(now time.Time) bool {
	if r.TTLSeconds <= 0 {
		return false
	}
	return now.After(r.CreatedAt.Add(time.Duration(r.TTLSeconds) * time.Second))
}
