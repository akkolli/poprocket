package apns

import (
	"context"
	"log/slog"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

type Payload map[string]any

type Client interface {
	Send(ctx context.Context, deviceToken string, payload Payload) error
}

func BuildPayload(req model.PushRequest) Payload {
	return Payload{
		"aps": map[string]any{
			"alert": map[string]string{
				"title": "PopRocket",
				"body":  "Homelab event",
			},
			"mutable-content": 1,
			"category":        "POPROCKET_EVENT",
			"thread-id":       req.BridgeID,
		},
		"bridge_id":         req.BridgeID,
		"event_id":          req.EventID,
		"encrypted_payload": req.EncryptedPayload,
	}
}

type LogClient struct {
	logger *slog.Logger
}

func NewLogClient(logger *slog.Logger) *LogClient {
	if logger == nil {
		logger = slog.Default()
	}
	return &LogClient{logger: logger}
}

func (c *LogClient) Send(ctx context.Context, deviceToken string, payload Payload) error {
	c.logger.InfoContext(ctx, "apns log delivery", "device_token_suffix", suffix(deviceToken, 6), "event_id", payload["event_id"])
	return nil
}

type MemoryClient struct {
	Deliveries []Delivery
	Err        error
}

type Delivery struct {
	DeviceToken string
	Payload     Payload
}

func (c *MemoryClient) Send(ctx context.Context, deviceToken string, payload Payload) error {
	if c.Err != nil {
		return c.Err
	}
	c.Deliveries = append(c.Deliveries, Delivery{DeviceToken: deviceToken, Payload: payload})
	return nil
}

func suffix(value string, n int) string {
	if len(value) <= n {
		return value
	}
	return value[len(value)-n:]
}
