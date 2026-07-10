package apns

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestTokenClientSendsAuthenticatedAlertAndCachesProviderToken(t *testing.T) {
	privateKey := testAPNSPrivateKey(t)
	var authorizations []string
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/3/device/aabb" {
			t.Errorf("request = %s %s", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("apns-topic"); got != "com.poprocket.app" {
			t.Errorf("apns-topic = %q", got)
		}
		if got := r.Header.Get("apns-push-type"); got != "alert" {
			t.Errorf("apns-push-type = %q", got)
		}
		if got := r.Header.Get("apns-priority"); got != "10" {
			t.Errorf("apns-priority = %q", got)
		}
		if got := r.Header.Get("apns-expiration"); got != "1800000300" {
			t.Errorf("apns-expiration = %q", got)
		}
		if got := r.Header.Get("apns-collapse-id"); got != "evt_test" {
			t.Errorf("apns-collapse-id = %q", got)
		}
		authorization := r.Header.Get("Authorization")
		if !strings.HasPrefix(authorization, "bearer ") || len(strings.Split(strings.TrimPrefix(authorization, "bearer "), ".")) != 3 {
			t.Errorf("authorization = %q", authorization)
		}
		authorizations = append(authorizations, authorization)
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client, err := NewTokenClient(TokenConfig{
		TeamID:        "TEAM123456",
		KeyID:         "KEY1234567",
		Topic:         "com.poprocket.app",
		PrivateKeyPEM: privateKey,
		Endpoint:      server.URL,
		HTTPClient:    server.Client(),
		Now:           func() time.Time { return time.Unix(1_800_000_000, 0) },
	})
	if err != nil {
		t.Fatal(err)
	}
	payload := Payload{"aps": map[string]any{"alert": map[string]string{"title": "Test", "body": "Hello"}}}
	options := DeliveryOptions{Expiration: time.Unix(1_800_000_300, 0), CollapseID: "evt_test"}
	if err := client.Send(context.Background(), "aabb", payload, options); err != nil {
		t.Fatal(err)
	}
	if err := client.Send(context.Background(), "aabb", payload, options); err != nil {
		t.Fatal(err)
	}
	if len(authorizations) != 2 || authorizations[0] != authorizations[1] {
		t.Fatalf("provider token was not reused: %v", authorizations)
	}
}

func TestTokenClientRejectsOversizedPayload(t *testing.T) {
	client, err := NewTokenClient(TokenConfig{
		TeamID:        "TEAM123456",
		KeyID:         "KEY1234567",
		Topic:         "com.poprocket.app",
		PrivateKeyPEM: testAPNSPrivateKey(t),
	})
	if err != nil {
		t.Fatal(err)
	}
	err = client.Send(context.Background(), "aabb", Payload{"value": strings.Repeat("x", maxAPNSPayloadBytes)}, DeliveryOptions{})
	if err == nil || !strings.Contains(err.Error(), "maximum") {
		t.Fatalf("error = %v", err)
	}
}

func testAPNSPrivateKey(t *testing.T) []byte {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	encoded, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: encoded})
}
