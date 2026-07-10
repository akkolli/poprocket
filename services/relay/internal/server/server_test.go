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
	app := New(mem, apnsClient, "test-token", nil)
	if _, err := mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios", Platform: "ios", APNSToken: "token"}); err != nil {
		t.Fatal(err)
	}

	body := `{"bridge_id":"bridge","event_id":"evt_1","encrypted_payload":"opaque","ttl_seconds":60}`
	req := httptest.NewRequest(http.MethodPost, "/v1/push", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer test-token")
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
	app := New(store.NewMemory(), &apns.MemoryClient{}, "test-token", nil)
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
	req.Header.Set("Authorization", "Bearer "+relayDeviceAccessToken("test-token", "bridge"))
	rec := httptest.NewRecorder()
	app.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
}

func TestDeviceRelayTokenIsBoundToBridge(t *testing.T) {
	app := New(store.NewMemory(), &apns.MemoryClient{}, "test-token", nil)
	body := `{"bridge_id":"bridge","device_id":"ios","apns_token":"aabb"}`

	wrong := httptest.NewRequest(http.MethodPost, "/v1/devices/register", strings.NewReader(body))
	wrong.Header.Set("Authorization", "Bearer "+relayDeviceAccessToken("test-token", "other-bridge"))
	wrongRecorder := httptest.NewRecorder()
	app.Routes().ServeHTTP(wrongRecorder, wrong)
	if wrongRecorder.Code != http.StatusUnauthorized {
		t.Fatalf("wrong bridge status = %d body = %s", wrongRecorder.Code, wrongRecorder.Body.String())
	}

	correct := httptest.NewRequest(http.MethodPost, "/v1/devices/register", strings.NewReader(body))
	correct.Header.Set("Authorization", "Bearer "+relayDeviceAccessToken("test-token", "bridge"))
	correctRecorder := httptest.NewRecorder()
	app.Routes().ServeHTTP(correctRecorder, correct)
	if correctRecorder.Code != http.StatusCreated {
		t.Fatalf("correct bridge status = %d body = %s", correctRecorder.Code, correctRecorder.Body.String())
	}
}

func TestProtectedEndpointsRequireRelayToken(t *testing.T) {
	app := New(store.NewMemory(), &apns.MemoryClient{}, "test-token", nil)
	req := httptest.NewRequest(http.MethodPost, "/v1/devices/register", strings.NewReader(`{"bridge_id":"bridge","device_id":"ios","apns_token":"aabb"}`))
	rec := httptest.NewRecorder()
	app.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("WWW-Authenticate") == "" {
		t.Fatal("WWW-Authenticate header is missing")
	}
}

func TestOversizedRequestIsRejectedBeforeDecode(t *testing.T) {
	app := New(store.NewMemory(), &apns.MemoryClient{}, "test-token", nil)
	req := httptest.NewRequest(http.MethodPost, "/v1/actions", strings.NewReader(strings.Repeat("x", maxJSONRequestBytes+1)))
	req.Header.Set("Authorization", "Bearer test-token")
	rec := httptest.NewRecorder()
	app.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d body = %s", rec.Code, rec.Body.String())
	}
}
