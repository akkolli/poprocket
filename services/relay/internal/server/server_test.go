package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/poprocket/poprocket/services/relay/internal/apns"
	"github.com/poprocket/poprocket/services/relay/internal/model"
	"github.com/poprocket/poprocket/services/relay/internal/store"
)

func TestPushDeliversOpaquePayloadToRegisteredDevices(t *testing.T) {
	apnsClient := &apns.MemoryClient{}
	mem := store.NewMemory()
	app := New(mem, apnsClient, nil)
	mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios", Platform: "ios", APNSToken: "token"})

	body := `{"bridge_id":"bridge","event_id":"evt_1","encrypted_payload":"opaque","ttl_seconds":60}`
	req := httptest.NewRequest(http.MethodPost, "/v1/push", strings.NewReader(body))
	rec := httptest.NewRecorder()
	app.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	if got := len(apnsClient.Deliveries); got != 1 {
		t.Fatalf("deliveries = %d", got)
	}
	payload, _ := json.Marshal(apnsClient.Deliveries[0].Payload)
	if strings.Contains(string(payload), "secret") {
		t.Fatalf("payload leaked secret: %s", payload)
	}
}

func TestExpiredActionIsRejected(t *testing.T) {
	app := New(store.NewMemory(), &apns.MemoryClient{}, nil)
	reqBody, err := json.Marshal(model.ActionRelayRequest{
		BridgeID:    "bridge",
		ActionRunID: "run_1",
		Payload:     json.RawMessage(`{"action_run_id":"run_1"}`),
		CreatedAt:   time.Now().Add(-2 * time.Minute).UTC(),
		TTLSeconds:  30,
	})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/actions", bytes.NewReader(reqBody))
	rec := httptest.NewRecorder()
	app.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
}
