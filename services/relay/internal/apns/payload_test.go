package apns

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

func TestBuildPayloadStaysOpaque(t *testing.T) {
	payload := BuildPayload(model.PushRequest{
		BridgeID:         "bridge-dev",
		EventID:          "evt_1",
		EncryptedPayload: "opaque-ciphertext",
		TTLSeconds:       60,
		CreatedAt:        time.Unix(100, 0).UTC(),
	})
	body, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	text := string(body)
	if !strings.Contains(text, "opaque-ciphertext") {
		t.Fatalf("payload missing opaque event reference: %s", text)
	}
	for _, secret := range []string{"host01", "job failed", "docker token", "192.168.1.10"} {
		if strings.Contains(strings.ToLower(text), secret) {
			t.Fatalf("payload leaked plaintext %q: %s", secret, text)
		}
	}
}

func TestBuildPayloadUsesDisplayAlertWhenProvided(t *testing.T) {
	payload := BuildPayload(model.PushRequest{
		BridgeID:         "bridge-dev",
		EventID:          "evt_1",
		AlertTitle:       "Fireman Security Alert",
		AlertBody:        "3 dependency issues need attention.",
		EncryptedPayload: "opaque-ciphertext",
		TTLSeconds:       60,
		CreatedAt:        time.Unix(100, 0).UTC(),
	})
	aps, ok := payload["aps"].(map[string]any)
	if !ok {
		t.Fatalf("aps missing: %#v", payload)
	}
	alert, ok := aps["alert"].(map[string]string)
	if !ok {
		t.Fatalf("alert missing: %#v", aps)
	}
	if alert["title"] != "Fireman Security Alert" {
		t.Fatalf("title = %q", alert["title"])
	}
	if alert["body"] != "3 dependency issues need attention." {
		t.Fatalf("body = %q", alert["body"])
	}
}
