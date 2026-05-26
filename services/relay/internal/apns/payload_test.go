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
		t.Fatalf("payload missing encrypted envelope: %s", text)
	}
	for _, secret := range []string{"host01", "job failed", "docker token", "192.168.1.10"} {
		if strings.Contains(strings.ToLower(text), secret) {
			t.Fatalf("payload leaked plaintext %q: %s", secret, text)
		}
	}
}
