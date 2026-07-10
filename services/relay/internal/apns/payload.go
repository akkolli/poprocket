package apns

import (
	"context"
	"log/slog"
	"strings"
	"time"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

type Payload map[string]any

type Client interface {
	Send(ctx context.Context, deviceToken string, payload Payload, options DeliveryOptions) error
}

type DeliveryOptions struct {
	Expiration time.Time
	CollapseID string
}

func BuildPayload(req model.PushRequest) Payload {
	title := compactAlertText(req.AlertTitle, 80)
	if title == "" {
		title = "PopRocket"
	}
	body := compactAlertText(req.AlertBody, 160)
	if body == "" {
		body = "Homelab event"
	}
	return Payload{
		"aps": map[string]any{
			"alert": map[string]string{
				"title": title,
				"body":  body,
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

func compactAlertText(value string, maxRunes int) string {
	value = strings.Join(strings.Fields(value), " ")
	if value == "" || maxRunes <= 0 {
		return ""
	}
	runes := []rune(value)
	if len(runes) <= maxRunes {
		return value
	}
	if maxRunes <= 3 {
		return string(runes[:maxRunes])
	}
	return string(runes[:maxRunes-3]) + "..."
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

func (c *LogClient) Send(ctx context.Context, deviceToken string, payload Payload, _ DeliveryOptions) error {
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
	Options     DeliveryOptions
}

func (c *MemoryClient) Send(ctx context.Context, deviceToken string, payload Payload, options DeliveryOptions) error {
	if c.Err != nil {
		return c.Err
	}
	c.Deliveries = append(c.Deliveries, Delivery{DeviceToken: deviceToken, Payload: payload, Options: options})
	return nil
}

func suffix(value string, n int) string {
	if len(value) <= n {
		return value
	}
	return value[len(value)-n:]
}
