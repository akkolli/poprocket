package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

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

	cfg := &config.Config{
		Bridge: config.BridgeConfig{
			ID:   "dev",
			Name: "Dev",
		},
	}
	server := New(cfg, store, security.NewVerifier(), bridgerelay.NewHTTPClient("", ""), nil)

	body := bytes.NewBufferString(`{
		"name": "Target",
		"mac": "02:00:5e:10:00:01",
		"ip_address": "192.168.1.50"
	}`)
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

	req = httptest.NewRequest(http.MethodGet, "/v1/wol-targets", nil)
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
