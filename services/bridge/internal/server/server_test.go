package server

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/config"
	"github.com/poprocket/poprocket/services/bridge/internal/model"
	bridgerelay "github.com/poprocket/poprocket/services/bridge/internal/relay"
	"github.com/poprocket/poprocket/services/bridge/internal/security"
	"github.com/poprocket/poprocket/services/bridge/internal/storage"
)

func TestWOLTargetAPIStoresTargetAndDerivesBroadcast(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{wolManageScope, wolReadScope}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	body := signedMutationBody(t, priv, "iphone", "wol-target:create", map[string]string{
		"id":         "wol_target",
		"name":       "Target",
		"mac":        "02:00:5e:10:00:01",
		"ip_address": "192.168.1.50",
	})
	req := httptest.NewRequest(http.MethodPost, "/v1/wol-targets", body)
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	var created struct {
		Target model.WOLTarget `json:"target"`
	}
	if err := json.NewDecoder(res.Body).Decode(&created); err != nil {
		t.Fatal(err)
	}
	if created.Target.ID == "" {
		t.Fatal("target id is empty")
	}
	if created.Target.BroadcastIP != "192.168.1.255" {
		t.Fatalf("broadcast_ip = %q", created.Target.BroadcastIP)
	}

	req = signedReadRequest(t, priv, "iphone", http.MethodGet, "/v1/wol-targets")
	res = httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	var listed struct {
		Targets []model.WOLTarget `json:"targets"`
	}
	if err := json.NewDecoder(res.Body).Decode(&listed); err != nil {
		t.Fatal(err)
	}
	if len(listed.Targets) != 1 || listed.Targets[0].ID != created.Target.ID {
		t.Fatalf("targets = %+v", listed.Targets)
	}
}

func TestEventAlertTextSupportsFiremanEvents(t *testing.T) {
	event := model.Event{
		Source: "fireman/dependencies",
	}
	if got := eventAlertTitle(event); got != "Fireman Security Alert" {
		t.Fatalf("title = %q", got)
	}
	if got := eventAlertBody(event); got != "Dependency security issue needs attention." {
		t.Fatalf("body = %q", got)
	}

	event.Title = "Critical dependency update"
	event.Body = "openssl needs attention"
	if got := eventAlertTitle(event); got != "Critical dependency update" {
		t.Fatalf("custom title = %q", got)
	}
	if got := eventAlertBody(event); got != "openssl needs attention" {
		t.Fatalf("custom body = %q", got)
	}
}

func TestEventAlertTextIsCompactedAndBounded(t *testing.T) {
	title := strings.Repeat("x", 100)
	event := model.Event{Title: "  " + title + "  "}
	if got := eventAlertTitle(event); len([]rune(got)) != 80 {
		t.Fatalf("title length = %d title = %q", len([]rune(got)), got)
	}
	if got := eventAlertBody(model.Event{Body: "line one\nline two"}); got != "line one line two" {
		t.Fatalf("body = %q", got)
	}
}

func TestNotificationIngestRequiresConfiguredToken(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge:   config.BridgeConfig{ID: "dev", Name: "Dev"},
		Security: config.SecurityConfig{NotificationToken: "notify-secret"},
	}
	app := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)
	body := `{"title":"Build failed","severity":"warning"}`

	unauthorized := httptest.NewRecorder()
	app.Routes().ServeHTTP(unauthorized, httptest.NewRequest(http.MethodPost, "/v1/notify", strings.NewReader(body)))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d body = %s", unauthorized.Code, unauthorized.Body.String())
	}

	req := httptest.NewRequest(http.MethodPost, "/v1/notify", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer notify-secret")
	authorized := httptest.NewRecorder()
	app.Routes().ServeHTTP(authorized, req)
	if authorized.Code != http.StatusAccepted {
		t.Fatalf("authorized status = %d body = %s", authorized.Code, authorized.Body.String())
	}
}

func TestPairingStartRequiresConfiguredAccessToken(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge:   config.BridgeConfig{ID: "dev", Name: "Dev"},
		Security: config.SecurityConfig{PairingAccessToken: "pairing-secret-1", PairingTTLSeconds: 300},
	}
	app := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	unauthorized := httptest.NewRecorder()
	app.Routes().ServeHTTP(unauthorized, httptest.NewRequest(http.MethodPost, "/v1/pairing/start", nil))
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status = %d body = %s", unauthorized.Code, unauthorized.Body.String())
	}

	req := httptest.NewRequest(http.MethodPost, "/v1/pairing/start", nil)
	req.Header.Set("Authorization", "Bearer pairing-secret-1")
	authorized := httptest.NewRecorder()
	app.Routes().ServeHTTP(authorized, req)
	if authorized.Code != http.StatusCreated {
		t.Fatalf("authorized status = %d body = %s", authorized.Code, authorized.Body.String())
	}
}

func TestPairingNeverGrantsScopesOutsideBridgePolicy(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{ID: "dev", Name: "Dev"},
		Security: config.SecurityConfig{
			PairingTTLSeconds: 300,
			DefaultScopes:     []string{"cards:read", "wol:wake:*"},
		},
		Relay: config.RelayConfig{Token: "relay-secret"},
	}
	app := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	start := httptest.NewRecorder()
	app.Routes().ServeHTTP(start, httptest.NewRequest(http.MethodPost, "/v1/pairing/start", nil))
	if start.Code != http.StatusCreated {
		t.Fatalf("start status = %d body = %s", start.Code, start.Body.String())
	}
	var started struct {
		PairingToken string `json:"pairing_token"`
	}
	if err := json.NewDecoder(start.Body).Decode(&started); err != nil {
		t.Fatal(err)
	}
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(model.PairingCompleteRequest{
		PairingToken: started.PairingToken,
		DeviceID:     "iphone",
		PublicKey:    base64.StdEncoding.EncodeToString(pub),
		Scopes:       []string{"cards:read", "command:run", "wol:wake:desktop", "wol:wake:*"},
	})
	if err != nil {
		t.Fatal(err)
	}
	complete := httptest.NewRecorder()
	app.Routes().ServeHTTP(complete, httptest.NewRequest(http.MethodPost, "/v1/pairing/complete", bytes.NewReader(body)))
	if complete.Code != http.StatusCreated {
		t.Fatalf("complete status = %d body = %s", complete.Code, complete.Body.String())
	}
	var response model.PairingCompleteResponse
	if err := json.NewDecoder(complete.Body).Decode(&response); err != nil {
		t.Fatal(err)
	}
	if got, want := strings.Join(response.Scopes, ","), "cards:read,wol:wake:desktop,wol:wake:*"; got != want {
		t.Fatalf("scopes = %q want %q", got, want)
	}
	if response.RelayAccessToken != relayDeviceAccessToken("relay-secret", "dev") {
		t.Fatalf("relay access token = %q", response.RelayAccessToken)
	}
}

func TestManagementMutationRequiresSignedEnvelope(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	body, err := json.Marshal(model.ActionEnvelope{
		ActionRunID:   "run_unsigned",
		ActionID:      "monitor:create",
		ActorDeviceID: "iphone",
		CreatedAt:     time.Now().UTC(),
		Parameters: map[string]string{
			"name": "SSH",
			"kind": "tcp",
			"host": "127.0.0.1",
			"port": "22",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/monitors", bytes.NewReader(body))
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestSensitiveReadRequiresSignedRequest(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	req := httptest.NewRequest(http.MethodGet, "/v1/monitors", nil)
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestSensitiveReadRequiresScope(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"cards:read"}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	req := signedReadRequest(t, priv, "iphone", http.MethodGet, "/v1/monitors")
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusForbidden {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestDirectWOLWakeRequiresSignedEnvelope(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		WOLTargets: []config.WOLTarget{
			{
				ID:          "desktop",
				Name:        "Desktop",
				MAC:         "02:00:5e:10:00:01",
				BroadcastIP: "192.168.1.255",
				UDPPort:     9,
			},
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	req := httptest.NewRequest(http.MethodPost, "/v1/wol/desktop/wake", bytes.NewBufferString(`{}`))
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestManagementMutationRequiresScope(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"cards:read"}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	req := httptest.NewRequest(http.MethodPost, "/v1/monitors", signedMutationBody(t, priv, "iphone", "monitor:create", map[string]string{
		"id":   "ssh",
		"name": "SSH",
		"kind": "tcp",
		"host": "127.0.0.1",
		"port": "22",
	}))
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusForbidden {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestHealthReportsBridgeCapabilities(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		CommandRunner: config.CommandRunnerConfig{
			Enabled:    true,
			AllowAdHoc: false,
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	req := httptest.NewRequest(http.MethodGet, "/v1/health", nil)
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	var body struct {
		Capabilities struct {
			CommandRunnerEnabled bool `json:"command_runner_enabled"`
			CommandRunnerAdHoc   bool `json:"command_runner_ad_hoc"`
			HealthMonitors       bool `json:"health_monitors"`
			WOL                  bool `json:"wol"`
		} `json:"capabilities"`
	}
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if !body.Capabilities.CommandRunnerEnabled {
		t.Fatal("command_runner_enabled is false")
	}
	if body.Capabilities.CommandRunnerAdHoc {
		t.Fatal("command_runner_ad_hoc is true")
	}
	if !body.Capabilities.HealthMonitors || !body.Capabilities.WOL {
		t.Fatalf("capabilities = %+v", body.Capabilities)
	}
}

func TestHealthMonitorAPIStoresAndChecksTCP(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			_ = conn.Close()
		}
	}()
	_, portText, err := net.SplitHostPort(listener.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		t.Fatal(err)
	}

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{monitorWriteScope, monitorReadScope}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	body := signedMutationBody(t, priv, "iphone", "monitor:create", map[string]string{
		"id":   "ssh",
		"name": "SSH",
		"kind": "tcp",
		"host": "127.0.0.1",
		"port": strconv.Itoa(port),
	})
	req := httptest.NewRequest(http.MethodPost, "/v1/monitors", body)
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusCreated {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	var created struct {
		Monitor model.HealthMonitor `json:"monitor"`
	}
	if err := json.NewDecoder(res.Body).Decode(&created); err != nil {
		t.Fatal(err)
	}
	if created.Monitor.ID == "" || created.Monitor.Status != "up" {
		t.Fatalf("created monitor = %+v", created.Monitor)
	}

	req = signedReadRequest(t, priv, "iphone", http.MethodGet, "/v1/monitors")
	res = httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
	var listed struct {
		Monitors []model.HealthMonitor `json:"monitors"`
	}
	if err := json.NewDecoder(res.Body).Decode(&listed); err != nil {
		t.Fatal(err)
	}
	if len(listed.Monitors) != 1 || listed.Monitors[0].Status != "up" || listed.Monitors[0].StatusChangedAt == nil {
		t.Fatalf("monitors = %+v", listed.Monitors)
	}
}

func TestConfigBackedResourcesAreReadOnly(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{monitorWriteScope, wolManageScope}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		Monitors: []config.MonitorConfig{
			{
				ID:             "router",
				Name:           "Router",
				Kind:           "tcp",
				Host:           "127.0.0.1",
				Port:           22,
				TimeoutSeconds: 1,
			},
		},
		WOLTargets: []config.WOLTarget{
			{
				ID:          "desktop",
				Name:        "Desktop",
				MAC:         "02:00:5e:10:00:01",
				BroadcastIP: "192.168.1.255",
				UDPPort:     9,
			},
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	tests := []struct {
		name       string
		method     string
		path       string
		actionID   string
		parameters map[string]string
	}{
		{
			name:     "update config monitor",
			method:   http.MethodPut,
			path:     "/v1/monitors/router",
			actionID: "monitor:update",
			parameters: map[string]string{
				"id":   "router",
				"name": "Router",
				"kind": "tcp",
				"host": "127.0.0.1",
				"port": "22",
			},
		},
		{
			name:     "delete config monitor",
			method:   http.MethodDelete,
			path:     "/v1/monitors/router",
			actionID: "monitor:delete",
			parameters: map[string]string{
				"id": "router",
			},
		},
		{
			name:     "update config wol target",
			method:   http.MethodPut,
			path:     "/v1/wol-targets/desktop",
			actionID: "wol-target:update",
			parameters: map[string]string{
				"id":           "desktop",
				"name":         "Desktop",
				"mac":          "02:00:5e:10:00:01",
				"broadcast_ip": "192.168.1.255",
			},
		},
		{
			name:     "delete config wol target",
			method:   http.MethodDelete,
			path:     "/v1/wol-targets/desktop",
			actionID: "wol-target:delete",
			parameters: map[string]string{
				"id": "desktop",
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(tt.method, tt.path, signedMutationBody(t, priv, "iphone", tt.actionID, tt.parameters))
			res := httptest.NewRecorder()
			server.Routes().ServeHTTP(res, req)
			if res.Code != http.StatusForbidden {
				t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
			}
		})
	}

	req := httptest.NewRequest(http.MethodPost, "/v1/monitors", signedMutationBody(t, priv, "iphone", "monitor:create", map[string]string{
		"id":   "router",
		"name": "Router Override",
		"kind": "tcp",
		"host": "127.0.0.1",
		"port": "22",
	}))
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusConflict {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func signedMutationBody(t *testing.T, privateKey ed25519.PrivateKey, deviceID, actionID string, parameters map[string]string) *bytes.Buffer {
	return signedMutationBodyAt(t, privateKey, deviceID, actionID, parameters, time.Now().UTC())
}

func signedMutationBodyAt(t *testing.T, privateKey ed25519.PrivateKey, deviceID, actionID string, parameters map[string]string, createdAt time.Time) *bytes.Buffer {
	t.Helper()
	env := model.ActionEnvelope{
		ActionRunID:   model.NewID("run"),
		ActionID:      actionID,
		ActorDeviceID: deviceID,
		Confirmed:     true,
		Parameters:    parameters,
		CreatedAt:     createdAt,
	}
	sig, err := security.SignAction(privateKey, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig
	body, err := json.Marshal(env)
	if err != nil {
		t.Fatal(err)
	}
	return bytes.NewBuffer(body)
}

func signedReadRequest(t *testing.T, privateKey ed25519.PrivateKey, deviceID, method, path string) *http.Request {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	createdAt := time.Now().UTC().Format(time.RFC3339)
	signature := security.RequestSignature{
		Method:        method,
		Path:          req.URL.Path,
		Query:         req.URL.RawQuery,
		ActorDeviceID: deviceID,
		CreatedAt:     createdAt,
	}
	sig, err := security.SignRequest(privateKey, signature)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("X-PopRocket-Device-ID", deviceID)
	req.Header.Set("X-PopRocket-Created-At", createdAt)
	req.Header.Set("X-PopRocket-Signature", sig)
	return req
}

func TestManagementMutationRejectsExpiredSignature(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{monitorWriteScope}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	req := httptest.NewRequest(http.MethodPost, "/v1/monitors", signedMutationBodyAt(t, priv, "iphone", "monitor:create", map[string]string{
		"id":   "ssh",
		"name": "SSH",
		"kind": "tcp",
		"host": "127.0.0.1",
		"port": "22",
	}, time.Now().Add(-10*time.Minute).UTC()))
	res := httptest.NewRecorder()
	server.Routes().ServeHTTP(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d body = %s", res.Code, res.Body.String())
	}
}

func TestAdHocCommandActionRunsSignedCommand(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"command:run"}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		CommandRunner: config.CommandRunnerConfig{
			Enabled:         true,
			AllowAdHoc:      true,
			Shell:           "/bin/sh",
			TimeoutSeconds:  5,
			MaxOutputBytes:  1024,
			AllowedPrefixes: []string{"printf "},
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	env := model.ActionEnvelope{
		ActionRunID:   "run_command",
		ActionID:      "command:run",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		Parameters:    map[string]string{"command": "printf hello"},
		CreatedAt:     time.Now().UTC(),
	}
	sig, err := security.SignAction(priv, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig

	result, status, err := server.ProcessAction(context.Background(), env)
	if err != nil {
		t.Fatalf("ProcessAction() status = %d error = %v", status, err)
	}
	if result.Status != "completed" || result.ResultMessage != "hello" {
		t.Fatalf("result = %+v", result)
	}
}

func TestAdHocCommandActionRejectsExpiredSignature(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := security.NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"command:run"}); err != nil {
		t.Fatal(err)
	}

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		CommandRunner: config.CommandRunnerConfig{
			Enabled:         true,
			AllowAdHoc:      true,
			Shell:           "/bin/sh",
			TimeoutSeconds:  5,
			MaxOutputBytes:  1024,
			AllowedPrefixes: []string{"printf "},
		},
	}
	server := New(cfg, store, verifier, bridgerelay.NewHTTPClient("", ""), nil)

	env := model.ActionEnvelope{
		ActionRunID:   "run_command",
		ActionID:      "command:run",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		Parameters:    map[string]string{"command": "printf hello"},
		CreatedAt:     time.Now().Add(-10 * time.Minute).UTC(),
	}
	sig, err := security.SignAction(priv, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig

	_, status, err := server.ProcessAction(context.Background(), env)
	if status != http.StatusUnauthorized || err == nil {
		t.Fatalf("ProcessAction() status = %d error = %v", status, err)
	}
}

func TestDirectActionRequiresSignedEnvelope(t *testing.T) {
	store, err := storage.OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
		CommandRunner: config.CommandRunnerConfig{
			Enabled:         true,
			AllowAdHoc:      true,
			Shell:           "/bin/sh",
			TimeoutSeconds:  5,
			MaxOutputBytes:  1024,
			AllowedPrefixes: []string{"printf "},
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)
	env := model.ActionEnvelope{
		ActionRunID:   "run_unsigned",
		ActionID:      "command:run",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		Parameters:    map[string]string{"command": "printf hello"},
		CreatedAt:     time.Now().UTC(),
	}

	_, status, err := server.ProcessAction(context.Background(), env)
	if status != http.StatusUnauthorized || err == nil {
		t.Fatalf("ProcessAction() status = %d error = %v", status, err)
	}
	if err.Error() != "signed action envelope is required" {
		t.Fatalf("error = %v", err)
	}
}
