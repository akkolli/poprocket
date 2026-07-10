package relay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type PushRequest struct {
	BridgeID         string    `json:"bridge_id"`
	EventID          string    `json:"event_id"`
	DeviceIDs        []string  `json:"device_ids,omitempty"`
	AlertTitle       string    `json:"alert_title,omitempty"`
	AlertBody        string    `json:"alert_body,omitempty"`
	EncryptedPayload string    `json:"encrypted_payload"`
	TTLSeconds       int       `json:"ttl_seconds"`
	CreatedAt        time.Time `json:"created_at"`
}

type Notifier interface {
	Push(ctx context.Context, req PushRequest) error
}

type HTTPClient struct {
	baseURL string
	token   string
	client  *http.Client
}

func NewHTTPClient(baseURL, token string) *HTTPClient {
	return &HTTPClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		token:   token,
		client:  &http.Client{Timeout: 5 * time.Second},
	}
}

func (c *HTTPClient) Push(ctx context.Context, req PushRequest) error {
	if c.baseURL == "" {
		return nil
	}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/v1/push", bytes.NewReader(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		httpReq.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := c.client.Do(httpReq)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4<<10))
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("relay push failed: %s", resp.Status)
	}
	return nil
}
