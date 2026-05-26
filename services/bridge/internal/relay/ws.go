package relay

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"time"

	"github.com/gorilla/websocket"
)

type BridgeWebSocketClient struct {
	URL      string
	BridgeID string
	Token    string
}

type BridgeMessage struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

func (c BridgeWebSocketClient) Run(ctx context.Context, handler func(context.Context, BridgeMessage) error) error {
	u, err := url.Parse(c.URL)
	if err != nil {
		return err
	}
	q := u.Query()
	q.Set("bridge_id", c.BridgeID)
	u.RawQuery = q.Encode()

	header := http.Header{}
	if c.Token != "" {
		header.Set("Authorization", "Bearer "+c.Token)
	}
	conn, _, err := websocket.DefaultDialer.DialContext(ctx, u.String(), header)
	if err != nil {
		return err
	}
	defer conn.Close()

	if err := conn.WriteJSON(map[string]any{"type": "hello", "bridge_id": c.BridgeID}); err != nil {
		return err
	}

	done := make(chan struct{})
	defer close(done)
	go func() {
		ticker := time.NewTicker(25 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-done:
				return
			case <-ticker.C:
				_ = conn.WriteJSON(map[string]any{"type": "ping"})
			}
		}
	}()

	for {
		_ = conn.SetReadDeadline(time.Now().Add(75 * time.Second))
		var msg BridgeMessage
		if err := conn.ReadJSON(&msg); err != nil {
			return err
		}
		if msg.Type == "pong" {
			continue
		}
		if err := handler(ctx, msg); err != nil {
			return err
		}
	}
}
