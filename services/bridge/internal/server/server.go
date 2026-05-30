package server

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/adapters"
	"github.com/poprocket/poprocket/services/bridge/internal/config"
	"github.com/poprocket/poprocket/services/bridge/internal/model"
	bridgerelay "github.com/poprocket/poprocket/services/bridge/internal/relay"
	"github.com/poprocket/poprocket/services/bridge/internal/security"
	"github.com/poprocket/poprocket/services/bridge/internal/storage"
	"github.com/poprocket/poprocket/services/bridge/internal/wol"
)

type Server struct {
	cfg          *config.Config
	store        storage.Store
	verifier     *security.Verifier
	relay        bridgerelay.Notifier
	logger       *slog.Logger
	bridgePubKey string

	mu       sync.Mutex
	sessions map[string]time.Time
	started  time.Time
}

type ActionResult struct {
	ActionRunID   string `json:"action_run_id"`
	Status        string `json:"status,omitempty"`
	ResultMessage string `json:"result_message,omitempty"`
	Duplicate     bool   `json:"duplicate,omitempty"`
}

type RelayActionEnvelope struct {
	model.ActionEnvelope
}

const (
	monitorWriteScope = "monitor:write"
	monitorReadScope  = "monitor:read"
	wolManageScope    = "wol:manage"
	wolReadScope      = "wol:read"

	signatureFreshnessWindow = 5 * time.Minute
)

func New(cfg *config.Config, store storage.Store, verifier *security.Verifier, relay bridgerelay.Notifier, logger *slog.Logger) *Server {
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		panic(err)
	}
	if logger == nil {
		logger = slog.Default()
	}
	return &Server{
		cfg:          cfg,
		store:        store,
		verifier:     verifier,
		relay:        relay,
		logger:       logger,
		bridgePubKey: base64.StdEncoding.EncodeToString(pub),
		sessions:     map[string]time.Time{},
		started:      time.Now().UTC(),
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", s.handleHealth)
	mux.HandleFunc("POST /v1/pairing/start", s.handlePairingStart)
	mux.HandleFunc("POST /v1/pairing/complete", s.handlePairingComplete)
	mux.HandleFunc("GET /v1/cards", s.handleCards)
	mux.HandleFunc("POST /v1/notify", s.handleNotify)
	mux.HandleFunc("POST /v1/actions/", s.handleAction)
	mux.HandleFunc("GET /v1/audit", s.handleAudit)
	mux.HandleFunc("GET /v1/monitors", s.handleHealthMonitors)
	mux.HandleFunc("POST /v1/monitors", s.handleCreateHealthMonitor)
	mux.HandleFunc("PUT /v1/monitors/", s.handleUpdateHealthMonitor)
	mux.HandleFunc("DELETE /v1/monitors/", s.handleDeleteHealthMonitor)
	mux.HandleFunc("GET /v1/wol-targets", s.handleWOLTargets)
	mux.HandleFunc("POST /v1/wol-targets", s.handleCreateWOLTarget)
	mux.HandleFunc("PUT /v1/wol-targets/", s.handleUpdateWOLTarget)
	mux.HandleFunc("DELETE /v1/wol-targets/", s.handleDeleteWOLTarget)
	mux.HandleFunc("POST /v1/wol/", s.handleWOL)
	return withJSON(mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"bridge_id":      s.cfg.Bridge.ID,
		"bridge_name":    s.cfg.Bridge.Name,
		"relay_url":      s.cfg.Relay.URL,
		"started_at":     s.started,
		"server_time":    time.Now().UTC(),
		"uptime_seconds": int(time.Since(s.started).Seconds()),
		"capabilities": map[string]any{
			"command_runner_enabled": s.cfg.CommandRunner.Enabled,
			"command_runner_ad_hoc":  s.cfg.CommandRunner.Enabled && s.cfg.CommandRunner.AllowAdHoc,
			"health_monitors":        true,
			"wol":                    true,
		},
	})
}

func (s *Server) handlePairingStart(w http.ResponseWriter, r *http.Request) {
	token := model.NewID("pair")
	expiresAt := time.Now().UTC().Add(time.Duration(s.cfg.Security.PairingTTLSeconds) * time.Second)
	s.mu.Lock()
	s.sessions[token] = expiresAt
	s.mu.Unlock()

	payload := model.PairingPayload{
		Version:           1,
		BridgeID:          s.cfg.Bridge.ID,
		BridgeName:        s.cfg.Bridge.Name,
		RelayURL:          s.cfg.Relay.URL,
		RelayWebSocketURL: s.cfg.Relay.WebSocketURL,
		PairingToken:      token,
		BridgePublicKey:   s.bridgePubKey,
		DirectURLs:        append([]string{}, s.cfg.Bridge.DirectURLs...),
		ExpiresAt:         expiresAt,
	}
	qr, err := json.Marshal(payload)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"pairing_token": token,
		"expires_at":    expiresAt,
		"payload":       payload,
		"qr_payload":    string(qr),
	})
}

func (s *Server) handlePairingComplete(w http.ResponseWriter, r *http.Request) {
	var req model.PairingCompleteRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.PairingToken == "" || req.DeviceID == "" || req.PublicKey == "" {
		writeError(w, http.StatusBadRequest, errors.New("pairing_token, device_id, and public_key are required"))
		return
	}
	s.mu.Lock()
	expiresAt, ok := s.sessions[req.PairingToken]
	if ok && time.Now().After(expiresAt) {
		delete(s.sessions, req.PairingToken)
		ok = false
	}
	if ok {
		delete(s.sessions, req.PairingToken)
	}
	s.mu.Unlock()
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.New("pairing token is invalid or expired"))
		return
	}
	scopes := req.Scopes
	if len(scopes) == 0 {
		scopes = append([]string{}, s.cfg.Security.DefaultScopes...)
	}
	if err := s.verifier.RegisterDevice(req.DeviceID, req.PublicKey, scopes); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	now := time.Now().UTC()
	if err := s.store.SaveDevice(r.Context(), model.DeviceRegistration{
		ID:        req.DeviceID,
		PublicKey: req.PublicKey,
		Scopes:    scopes,
		CreatedAt: now,
		UpdatedAt: now,
	}); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"device_id": req.DeviceID,
		"scopes":    scopes,
	})
}

func (s *Server) handleCards(w http.ResponseWriter, r *http.Request) {
	if status, err := s.authorizeRead(r, []string{"cards:read"}); err != nil {
		writeError(w, status, err)
		return
	}
	now := time.Now().UTC()
	reader := adapters.Reader{}
	cards := []model.CardSnapshot{}
	for _, card := range s.cfg.Cards {
		staleAfter := card.StaleAfterSeconds
		if staleAfter == 0 {
			staleAfter = 300
		}
		value, err := reader.ReadCard(r.Context(), card)
		status := "fresh"
		stale := false
		var errorMessage string
		if err != nil {
			status = "error"
			stale = true
			errorMessage = err.Error()
			value = map[string]any{
				"configured": true,
				"source":     sourceSummary(card.Source),
			}
		}
		cards = append(cards, model.CardSnapshot{
			ID:                card.ID,
			Title:             card.Title,
			Kind:              card.Kind,
			Status:            status,
			UpdatedAt:         now,
			StaleAfterSeconds: staleAfter,
			Stale:             stale,
			Error:             errorMessage,
			Value:             value,
		})
	}
	writeJSON(w, http.StatusOK, map[string]any{"cards": cards})
}

func (s *Server) handleNotify(w http.ResponseWriter, r *http.Request) {
	var event model.Event
	if err := decodeJSON(r, &event); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	event.Normalize(time.Now())
	created, err := s.store.SaveEvent(r.Context(), event)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if created {
		if err := s.relay.Push(r.Context(), bridgerelay.PushRequest{
			BridgeID:         s.cfg.Bridge.ID,
			EventID:          event.EventID,
			EncryptedPayload: opaqueEventPayload(s.cfg.Bridge.ID, event),
			TTLSeconds:       event.TTLSeconds,
			CreatedAt:        event.CreatedAt,
		}); err != nil {
			s.logger.Warn("relay push failed", "event_id", event.EventID, "error", err)
		}
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"event_id":  event.EventID,
		"duplicate": !created,
	})
}

func (s *Server) handleAction(w http.ResponseWriter, r *http.Request) {
	actionRunID := strings.TrimPrefix(r.URL.Path, "/v1/actions/")
	if actionRunID == "" {
		writeError(w, http.StatusBadRequest, errors.New("action_run_id is required"))
		return
	}
	var env model.ActionEnvelope
	if err := decodeJSON(r, &env); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if env.ActionRunID == "" {
		env.ActionRunID = actionRunID
	}
	if env.ActionRunID != actionRunID {
		writeError(w, http.StatusBadRequest, errors.New("path action_run_id does not match body"))
		return
	}
	result, status, err := s.ProcessAction(r.Context(), env)
	if err != nil {
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusAccepted, result)
}

func (s *Server) ProcessAction(ctx context.Context, env model.ActionEnvelope) (ActionResult, int, error) {
	if env.ActionRunID == "" {
		return ActionResult{}, http.StatusBadRequest, errors.New("action_run_id is required")
	}
	if env.ActionID == "" || env.ActorDeviceID == "" || env.Signature == "" {
		return ActionResult{}, http.StatusUnauthorized, errors.New("signed action envelope is required")
	}
	if env.CreatedAt.IsZero() {
		return ActionResult{}, http.StatusBadRequest, errors.New("created_at is required")
	}
	if err := validateSignedTime(env.CreatedAt, "signed action envelope"); err != nil {
		s.recordDenied(ctx, env, err.Error())
		return ActionResult{}, http.StatusUnauthorized, err
	}
	action, ok, err := s.findAction(ctx, env.ActionID)
	if err != nil {
		return ActionResult{}, http.StatusInternalServerError, err
	}
	if !ok {
		s.recordDenied(ctx, env, "unknown action")
		return ActionResult{}, http.StatusNotFound, fmt.Errorf("action %s not found", env.ActionID)
	}
	if action.RequiresConfirmation && !env.Confirmed {
		s.recordDenied(ctx, env, "confirmation required")
		return ActionResult{}, http.StatusForbidden, errors.New("confirmation required")
	}
	if err := s.verifier.VerifyAction(env, action.Scopes); err != nil {
		s.recordDenied(ctx, env, err.Error())
		return ActionResult{}, http.StatusForbidden, err
	}

	record := model.ActionRecord{
		ActionRunID:   env.ActionRunID,
		EventID:       env.EventID,
		ActionID:      env.ActionID,
		ActorDeviceID: env.ActorDeviceID,
		Status:        "accepted",
		CreatedAt:     time.Now().UTC(),
	}
	created, err := s.store.UpsertAction(ctx, record)
	if err != nil {
		return ActionResult{}, http.StatusInternalServerError, err
	}
	if !created {
		return ActionResult{ActionRunID: env.ActionRunID, Duplicate: true}, http.StatusAccepted, nil
	}

	status, resultMessage := s.executeAction(ctx, action, env.Parameters)
	if err := s.store.CompleteAction(ctx, env.ActionRunID, status, resultMessage, time.Now().UTC()); err != nil {
		return ActionResult{}, http.StatusInternalServerError, err
	}
	return ActionResult{ActionRunID: env.ActionRunID, Status: status, ResultMessage: resultMessage}, http.StatusAccepted, nil
}

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	if status, err := s.authorizeRead(r, []string{"audit:read"}); err != nil {
		writeError(w, status, err)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	records, err := s.store.ListActions(r.Context(), limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"actions": records})
}

func (s *Server) handleHealthMonitors(w http.ResponseWriter, r *http.Request) {
	if status, err := s.authorizeRead(r, []string{monitorReadScope}); err != nil {
		writeError(w, status, err)
		return
	}
	monitors, err := s.listHealthMonitors(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	checked, err := s.checkHealthMonitors(r.Context(), monitors)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"monitors": checked})
}

func (s *Server) handleCreateHealthMonitor(w http.ResponseWriter, r *http.Request) {
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "monitor:create", []string{monitorWriteScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	req, err := healthMonitorRequestFromParameters(env.Parameters)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if duplicate {
		monitor, ok, err := s.findHealthMonitor(r.Context(), req.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			writeError(w, http.StatusConflict, fmt.Errorf("duplicate action %s has no monitor result", env.ActionRunID))
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"monitor": monitor, "duplicate": true})
		return
	}
	monitor, err := normalizeHealthMonitorRequest(req, nil)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if _, ok, err := s.findHealthMonitor(r.Context(), monitor.ID); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	} else if ok {
		s.completeMutation(r.Context(), env, "failed", "monitor already exists")
		writeError(w, http.StatusConflict, fmt.Errorf("monitor %s already exists", monitor.ID))
		return
	}
	now := time.Now().UTC()
	monitor.CreatedAt = &now
	monitor.UpdatedAt = &now
	if err := s.store.SaveHealthMonitor(r.Context(), monitor); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	monitor.Source = "user"
	checked, err := s.checkHealthMonitor(r.Context(), monitor)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.completeMutation(r.Context(), env, "completed", "monitor created")
	writeJSON(w, http.StatusCreated, map[string]any{"monitor": checked})
}

func (s *Server) handleUpdateHealthMonitor(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/v1/monitors/")
	if id == "" || strings.Contains(id, "/") {
		writeError(w, http.StatusBadRequest, errors.New("monitor id is required"))
		return
	}
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "monitor:update", []string{monitorWriteScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	req, err := healthMonitorRequestFromParameters(env.Parameters)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.ID != id {
		s.completeMutation(r.Context(), env, "failed", "path monitor id does not match signed parameters")
		writeError(w, http.StatusBadRequest, errors.New("path monitor id does not match signed parameters"))
		return
	}
	if duplicate {
		monitor, ok, err := s.findHealthMonitor(r.Context(), id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			writeError(w, http.StatusConflict, fmt.Errorf("duplicate action %s has no monitor result", env.ActionRunID))
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"monitor": monitor, "duplicate": true})
		return
	}
	existing, ok, err := s.findHealthMonitor(r.Context(), id)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		s.completeMutation(r.Context(), env, "failed", "monitor not found")
		writeError(w, http.StatusNotFound, fmt.Errorf("monitor %s not found", id))
		return
	}
	if existing.Source != "user" {
		s.completeMutation(r.Context(), env, "failed", "only user-managed monitors can be edited")
		writeError(w, http.StatusForbidden, errors.New("only user-managed monitors can be edited"))
		return
	}
	monitor, err := normalizeHealthMonitorRequest(req, &existing)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	now := time.Now().UTC()
	monitor.CreatedAt = existing.CreatedAt
	if monitor.CreatedAt == nil {
		monitor.CreatedAt = &now
	}
	monitor.UpdatedAt = &now
	if err := s.store.SaveHealthMonitor(r.Context(), monitor); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	monitor.Source = "user"
	checked, err := s.checkHealthMonitor(r.Context(), monitor)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.completeMutation(r.Context(), env, "completed", "monitor updated")
	writeJSON(w, http.StatusOK, map[string]any{"monitor": checked})
}

func (s *Server) handleDeleteHealthMonitor(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/v1/monitors/")
	if id == "" || strings.Contains(id, "/") {
		writeError(w, http.StatusBadRequest, errors.New("monitor id is required"))
		return
	}
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "monitor:delete", []string{monitorWriteScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	if signedID := strings.TrimSpace(env.Parameters["id"]); signedID != id {
		s.completeMutation(r.Context(), env, "failed", "path monitor id does not match signed parameters")
		writeError(w, http.StatusBadRequest, errors.New("path monitor id does not match signed parameters"))
		return
	}
	if duplicate {
		writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "monitor_id": id, "duplicate": true})
		return
	}
	existing, ok, err := s.findHealthMonitor(r.Context(), id)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		s.completeMutation(r.Context(), env, "failed", "monitor not found")
		writeError(w, http.StatusNotFound, fmt.Errorf("monitor %s not found", id))
		return
	}
	if existing.Source != "user" {
		s.completeMutation(r.Context(), env, "failed", "only user-managed monitors can be deleted")
		writeError(w, http.StatusForbidden, errors.New("only user-managed monitors can be deleted"))
		return
	}
	if err := s.store.DeleteHealthMonitor(r.Context(), id); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.completeMutation(r.Context(), env, "completed", "monitor deleted")
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "monitor_id": id})
}

func (s *Server) handleWOLTargets(w http.ResponseWriter, r *http.Request) {
	if status, err := s.authorizeRead(r, []string{wolReadScope}); err != nil {
		writeError(w, status, err)
		return
	}
	targets, err := s.listWOLTargets(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"targets": targets})
}

func (s *Server) handleCreateWOLTarget(w http.ResponseWriter, r *http.Request) {
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "wol-target:create", []string{wolManageScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	req, err := wolTargetRequestFromParameters(env.Parameters)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if duplicate {
		target, ok, err := s.findWOLTarget(r.Context(), req.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			writeError(w, http.StatusConflict, fmt.Errorf("duplicate action %s has no wol target result", env.ActionRunID))
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"target": target, "duplicate": true})
		return
	}
	target, err := normalizeWOLTargetRequest(req, nil)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if _, ok, err := s.findWOLTarget(r.Context(), target.ID); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	} else if ok {
		s.completeMutation(r.Context(), env, "failed", "wol target already exists")
		writeError(w, http.StatusConflict, fmt.Errorf("wol target %s already exists", target.ID))
		return
	}
	now := time.Now().UTC()
	target.CreatedAt = &now
	target.UpdatedAt = &now
	if err := s.store.SaveWOLTarget(r.Context(), target); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	target.Source = "user"
	s.completeMutation(r.Context(), env, "completed", "wol target created")
	writeJSON(w, http.StatusCreated, map[string]any{"target": target})
}

func (s *Server) handleUpdateWOLTarget(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/v1/wol-targets/")
	if id == "" || strings.Contains(id, "/") {
		writeError(w, http.StatusBadRequest, errors.New("target id is required"))
		return
	}
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "wol-target:update", []string{wolManageScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	req, err := wolTargetRequestFromParameters(env.Parameters)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.ID != id {
		s.completeMutation(r.Context(), env, "failed", "path target id does not match signed parameters")
		writeError(w, http.StatusBadRequest, errors.New("path target id does not match signed parameters"))
		return
	}
	if duplicate {
		target, ok, err := s.findWOLTarget(r.Context(), id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			writeError(w, http.StatusConflict, fmt.Errorf("duplicate action %s has no wol target result", env.ActionRunID))
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"target": target, "duplicate": true})
		return
	}
	existing, ok, err := s.findWOLTarget(r.Context(), id)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		s.completeMutation(r.Context(), env, "failed", "wol target not found")
		writeError(w, http.StatusNotFound, fmt.Errorf("wol target %s not found", id))
		return
	}
	if existing.Source != "user" {
		s.completeMutation(r.Context(), env, "failed", "only user-managed wol targets can be edited")
		writeError(w, http.StatusForbidden, errors.New("only user-managed wol targets can be edited"))
		return
	}
	target, err := normalizeWOLTargetRequest(req, &existing)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusBadRequest, err)
		return
	}
	now := time.Now().UTC()
	target.CreatedAt = existing.CreatedAt
	if target.CreatedAt == nil {
		target.CreatedAt = &now
	}
	target.UpdatedAt = &now
	if err := s.store.SaveWOLTarget(r.Context(), target); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	target.Source = "user"
	s.completeMutation(r.Context(), env, "completed", "wol target updated")
	writeJSON(w, http.StatusOK, map[string]any{"target": target})
}

func (s *Server) handleDeleteWOLTarget(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/v1/wol-targets/")
	if id == "" || strings.Contains(id, "/") {
		writeError(w, http.StatusBadRequest, errors.New("target id is required"))
		return
	}
	env, duplicate, status, err := s.authorizeMutation(r.Context(), r, "wol-target:delete", []string{wolManageScope})
	if err != nil {
		writeError(w, status, err)
		return
	}
	if signedID := strings.TrimSpace(env.Parameters["id"]); signedID != id {
		s.completeMutation(r.Context(), env, "failed", "path target id does not match signed parameters")
		writeError(w, http.StatusBadRequest, errors.New("path target id does not match signed parameters"))
		return
	}
	if duplicate {
		writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "target_id": id, "duplicate": true})
		return
	}
	existing, ok, err := s.findWOLTarget(r.Context(), id)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		s.completeMutation(r.Context(), env, "failed", "wol target not found")
		writeError(w, http.StatusNotFound, fmt.Errorf("wol target %s not found", id))
		return
	}
	if existing.Source != "user" {
		s.completeMutation(r.Context(), env, "failed", "only user-managed wol targets can be deleted")
		writeError(w, http.StatusForbidden, errors.New("only user-managed wol targets can be deleted"))
		return
	}
	if err := s.store.DeleteWOLTarget(r.Context(), id); err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.completeMutation(r.Context(), env, "completed", "wol target deleted")
	writeJSON(w, http.StatusOK, map[string]any{"deleted": true, "target_id": id})
}

func (s *Server) handleWOL(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/wol/")
	targetID, ok := strings.CutSuffix(path, "/wake")
	if !ok || targetID == "" {
		writeError(w, http.StatusBadRequest, errors.New("expected /v1/wol/{target_id}/wake"))
		return
	}
	env, duplicate, statusCode, err := s.authorizeMutation(r.Context(), r, "wol:"+targetID, []string{"wol:wake:" + targetID})
	if err != nil {
		writeError(w, statusCode, err)
		return
	}
	if duplicate {
		writeJSON(w, http.StatusAccepted, map[string]any{
			"action_run_id": env.ActionRunID,
			"target_id":     targetID,
			"duplicate":     true,
		})
		return
	}
	target, ok, err := s.findWOLTarget(r.Context(), targetID)
	if err != nil {
		s.completeMutation(r.Context(), env, "failed", err.Error())
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !ok {
		s.completeMutation(r.Context(), env, "failed", "wol target not found")
		writeError(w, http.StatusNotFound, fmt.Errorf("wol target %s not found", targetID))
		return
	}
	status, result := "completed", "magic packet sent"
	if err := wol.Send(r.Context(), target.MAC, target.BroadcastIP, target.UDPPort); err != nil {
		status, result = "failed", err.Error()
	}
	s.completeMutation(r.Context(), env, status, result)
	writeJSON(w, http.StatusAccepted, map[string]any{
		"action_run_id":  env.ActionRunID,
		"target_id":      targetID,
		"status":         status,
		"result_message": result,
	})
}

func (s *Server) authorizeRead(r *http.Request, requiredScopes []string) (int, error) {
	createdAt := strings.TrimSpace(r.Header.Get("X-PopRocket-Created-At"))
	if createdAt == "" || strings.TrimSpace(r.Header.Get("X-PopRocket-Device-ID")) == "" || strings.TrimSpace(r.Header.Get("X-PopRocket-Signature")) == "" {
		return http.StatusUnauthorized, errors.New("signed bridge request is required")
	}
	created, err := time.Parse(time.RFC3339, createdAt)
	if err != nil {
		return http.StatusUnauthorized, errors.New("signed bridge request has an invalid created_at")
	}
	if err := validateSignedTime(created, "signed bridge request"); err != nil {
		return http.StatusUnauthorized, err
	}
	req := security.RequestSignature{
		Method:        r.Method,
		Path:          r.URL.Path,
		Query:         r.URL.RawQuery,
		ActorDeviceID: strings.TrimSpace(r.Header.Get("X-PopRocket-Device-ID")),
		CreatedAt:     created.UTC().Format(time.RFC3339),
		Signature:     strings.TrimSpace(r.Header.Get("X-PopRocket-Signature")),
	}
	if err := s.verifier.VerifyRequest(req, requiredScopes); err != nil {
		return http.StatusForbidden, err
	}
	return http.StatusOK, nil
}

func (s *Server) authorizeMutation(ctx context.Context, r *http.Request, expectedActionID string, requiredScopes []string) (model.ActionEnvelope, bool, int, error) {
	var env model.ActionEnvelope
	if err := json.NewDecoder(r.Body).Decode(&env); err != nil {
		return model.ActionEnvelope{}, false, http.StatusBadRequest, err
	}
	if env.ActionRunID == "" || env.ActionID == "" || env.ActorDeviceID == "" || env.Signature == "" {
		return env, false, http.StatusUnauthorized, errors.New("signed action envelope is required")
	}
	if env.ActionID != expectedActionID {
		return env, false, http.StatusBadRequest, fmt.Errorf("action_id must be %s", expectedActionID)
	}
	if env.CreatedAt.IsZero() {
		return env, false, http.StatusBadRequest, errors.New("created_at is required")
	}
	if err := validateSignedTime(env.CreatedAt, "signed action envelope"); err != nil {
		s.recordDenied(ctx, env, err.Error())
		return env, false, http.StatusUnauthorized, err
	}
	if err := s.verifier.VerifyAction(env, requiredScopes); err != nil {
		s.recordDenied(ctx, env, err.Error())
		return env, false, http.StatusForbidden, err
	}
	record := model.ActionRecord{
		ActionRunID:   env.ActionRunID,
		EventID:       env.EventID,
		ActionID:      env.ActionID,
		ActorDeviceID: env.ActorDeviceID,
		Status:        "accepted",
		CreatedAt:     time.Now().UTC(),
	}
	created, err := s.store.UpsertAction(ctx, record)
	if err != nil {
		return env, false, http.StatusInternalServerError, err
	}
	return env, !created, http.StatusOK, nil
}

func (s *Server) completeMutation(ctx context.Context, env model.ActionEnvelope, status, resultMessage string) {
	if env.ActionRunID == "" {
		return
	}
	_ = s.store.CompleteAction(ctx, env.ActionRunID, status, resultMessage, time.Now().UTC())
}

func healthMonitorRequestFromParameters(parameters map[string]string) (model.HealthMonitorRequest, error) {
	port, err := optionalIntParameter(parameters, "port")
	if err != nil {
		return model.HealthMonitorRequest{}, err
	}
	timeoutSeconds, err := optionalIntParameter(parameters, "timeout_seconds")
	if err != nil {
		return model.HealthMonitorRequest{}, err
	}
	return model.HealthMonitorRequest{
		ID:             strings.TrimSpace(parameters["id"]),
		Name:           strings.TrimSpace(parameters["name"]),
		Kind:           strings.TrimSpace(parameters["kind"]),
		Host:           strings.TrimSpace(parameters["host"]),
		Port:           port,
		URL:            strings.TrimSpace(parameters["url"]),
		TimeoutSeconds: timeoutSeconds,
	}, nil
}

func wolTargetRequestFromParameters(parameters map[string]string) (model.WOLTargetRequest, error) {
	subnetBits, err := optionalIntParameter(parameters, "subnet_bits")
	if err != nil {
		return model.WOLTargetRequest{}, err
	}
	udpPort, err := optionalIntParameter(parameters, "udp_port")
	if err != nil {
		return model.WOLTargetRequest{}, err
	}
	return model.WOLTargetRequest{
		ID:          strings.TrimSpace(parameters["id"]),
		Name:        strings.TrimSpace(parameters["name"]),
		MAC:         strings.TrimSpace(parameters["mac"]),
		IPAddress:   strings.TrimSpace(parameters["ip_address"]),
		BroadcastIP: strings.TrimSpace(parameters["broadcast_ip"]),
		SubnetBits:  subnetBits,
		UDPPort:     udpPort,
	}, nil
}

func optionalIntParameter(parameters map[string]string, key string) (int, error) {
	value := strings.TrimSpace(parameters[key])
	if value == "" {
		return 0, nil
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be a number", key)
	}
	return parsed, nil
}

func (s *Server) executeAction(ctx context.Context, action config.ActionConfig, parameters map[string]string) (string, string) {
	switch action.Kind {
	case "audit":
		return "completed", "acknowledged"
	case "wol":
		target, ok, err := s.findWOLTarget(ctx, action.TargetID)
		if err != nil {
			return "failed", err.Error()
		}
		if !ok {
			return "failed", "wol target not found"
		}
		if err := wol.Send(ctx, target.MAC, target.BroadcastIP, target.UDPPort); err != nil {
			return "failed", err.Error()
		}
		return "completed", "magic packet sent"
	case "docker_container":
		if err := adapters.RunDockerContainerAction(ctx, action.DockerHost, action.TargetID, action.Operation); err != nil {
			return "failed", err.Error()
		}
		return "completed", "docker " + action.Operation + " accepted"
	case "command":
		if !s.cfg.CommandRunner.Enabled {
			return "failed", "command runner is disabled"
		}
		command := action.Command
		if command == "" {
			command = parameters["command"]
		}
		timeout := s.cfg.CommandRunner.TimeoutSeconds
		if action.TimeoutSeconds > 0 {
			timeout = action.TimeoutSeconds
		}
		output, err := adapters.RunCommandAction(ctx, command, adapters.CommandOptions{
			Shell:           s.cfg.CommandRunner.Shell,
			TimeoutSeconds:  timeout,
			MaxOutputBytes:  s.cfg.CommandRunner.MaxOutputBytes,
			AllowedPrefixes: s.cfg.CommandRunner.AllowedPrefixes,
		})
		if err != nil {
			return "failed", err.Error()
		}
		return "completed", output
	default:
		return "failed", "unsupported action kind"
	}
}

func (s *Server) findAction(ctx context.Context, actionID string) (config.ActionConfig, bool, error) {
	if action, ok := s.cfg.FindAction(actionID); ok {
		return action, true, nil
	}
	if actionID == "command:run" && s.cfg.CommandRunner.AllowAdHoc {
		return config.ActionConfig{
			ID:                   actionID,
			Title:                "Run Command",
			Kind:                 "command",
			RequiresConfirmation: true,
			Scopes:               []string{"command:run"},
		}, true, nil
	}
	targetID, ok := strings.CutPrefix(actionID, "wol:")
	if !ok || targetID == "" {
		return config.ActionConfig{}, false, nil
	}
	target, ok, err := s.findWOLTarget(ctx, targetID)
	if err != nil || !ok {
		return config.ActionConfig{}, ok, err
	}
	return config.ActionConfig{
		ID:                   actionID,
		Title:                "Wake " + target.Name,
		Kind:                 "wol",
		TargetID:             target.ID,
		RequiresConfirmation: true,
		Scopes:               []string{"wol:wake:" + target.ID},
	}, true, nil
}

func (s *Server) findWOLTarget(ctx context.Context, id string) (model.WOLTarget, bool, error) {
	targets, err := s.listWOLTargets(ctx)
	if err != nil {
		return model.WOLTarget{}, false, err
	}
	for _, target := range targets {
		if target.ID == id {
			return target, true, nil
		}
	}
	return model.WOLTarget{}, false, nil
}

func (s *Server) findHealthMonitor(ctx context.Context, id string) (model.HealthMonitor, bool, error) {
	monitors, err := s.listHealthMonitors(ctx)
	if err != nil {
		return model.HealthMonitor{}, false, err
	}
	for _, monitor := range monitors {
		if monitor.ID == id {
			return monitor, true, nil
		}
	}
	return model.HealthMonitor{}, false, nil
}

func (s *Server) listHealthMonitors(ctx context.Context) ([]model.HealthMonitor, error) {
	byID := make(map[string]model.HealthMonitor, len(s.cfg.Monitors))
	for _, monitor := range s.cfg.Monitors {
		byID[monitor.ID] = healthMonitorFromConfig(monitor)
	}
	storedMonitors, err := s.store.ListHealthMonitors(ctx)
	if err != nil {
		return nil, err
	}
	for _, monitor := range storedMonitors {
		monitor.Source = "user"
		byID[monitor.ID] = monitor
	}
	wolTargets, err := s.listWOLTargets(ctx)
	if err != nil {
		return nil, err
	}
	for _, target := range wolTargets {
		if target.IPAddress == "" {
			continue
		}
		id := "wol:" + target.ID
		if _, exists := byID[id]; exists {
			continue
		}
		byID[id] = model.HealthMonitor{
			ID:             id,
			Name:           target.Name,
			Kind:           "tcp",
			Host:           target.IPAddress,
			Port:           22,
			TimeoutSeconds: 3,
			Source:         "wol",
		}
	}
	monitors := make([]model.HealthMonitor, 0, len(byID))
	for _, monitor := range byID {
		monitors = append(monitors, monitor)
	}
	sort.Slice(monitors, func(i, j int) bool {
		left := statusRank(monitors[i].Status)
		right := statusRank(monitors[j].Status)
		if left != right {
			return left < right
		}
		leftName := strings.ToLower(monitors[i].Name)
		rightName := strings.ToLower(monitors[j].Name)
		if leftName == rightName {
			return monitors[i].ID < monitors[j].ID
		}
		return leftName < rightName
	})
	return monitors, nil
}

func (s *Server) checkHealthMonitor(ctx context.Context, monitor model.HealthMonitor) (model.HealthMonitor, error) {
	start := time.Now()
	status, message := runHealthCheck(ctx, monitor)
	now := time.Now().UTC()
	monitor.Status = status
	monitor.Message = message
	monitor.ResponseTimeMS = time.Since(start).Milliseconds()
	monitor.CheckedAt = &now
	changedAt := now
	if previous, ok, err := s.store.GetHealthMonitorState(ctx, monitor.ID); err != nil {
		return model.HealthMonitor{}, err
	} else if ok && previous.Status == status {
		changedAt = previous.StatusChangedAt
	}
	monitor.StatusChangedAt = &changedAt
	if err := s.store.SaveHealthMonitorState(ctx, model.HealthMonitorState{
		ID:              monitor.ID,
		Status:          status,
		CheckedAt:       now,
		StatusChangedAt: changedAt,
	}); err != nil {
		return model.HealthMonitor{}, err
	}
	return monitor, nil
}

func (s *Server) checkHealthMonitors(ctx context.Context, monitors []model.HealthMonitor) ([]model.HealthMonitor, error) {
	if len(monitors) == 0 {
		return monitors, nil
	}
	checked := make([]model.HealthMonitor, len(monitors))
	errs := make(chan error, len(monitors))
	limit := 8
	if len(monitors) < limit {
		limit = len(monitors)
	}
	sem := make(chan struct{}, limit)
	var wg sync.WaitGroup
	for i, monitor := range monitors {
		i, monitor := i, monitor
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				errs <- ctx.Err()
				return
			}
			result, err := s.checkHealthMonitor(ctx, monitor)
			if err != nil {
				errs <- err
				return
			}
			checked[i] = result
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			return nil, err
		}
	}
	return checked, nil
}

func runHealthCheck(ctx context.Context, monitor model.HealthMonitor) (string, string) {
	timeout := time.Duration(monitor.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = 3 * time.Second
	}
	checkCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	switch monitor.Kind {
	case "http":
		req, err := http.NewRequestWithContext(checkCtx, http.MethodGet, monitor.URL, nil)
		if err != nil {
			return "down", err.Error()
		}
		req.Header.Set("User-Agent", "PopRocket-Bridge/1")
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			return "down", err.Error()
		}
		defer res.Body.Close()
		if res.StatusCode >= 200 && res.StatusCode < 400 {
			return "up", res.Status
		}
		return "down", res.Status
	case "tcp":
		dialer := net.Dialer{Timeout: timeout}
		conn, err := dialer.DialContext(checkCtx, "tcp", net.JoinHostPort(monitor.Host, strconv.Itoa(monitor.Port)))
		if err != nil {
			return "down", err.Error()
		}
		_ = conn.Close()
		return "up", "tcp connected"
	default:
		return "down", "unsupported monitor kind"
	}
}

func (s *Server) listWOLTargets(ctx context.Context) ([]model.WOLTarget, error) {
	byID := make(map[string]model.WOLTarget, len(s.cfg.WOLTargets))
	for _, target := range s.cfg.WOLTargets {
		byID[target.ID] = wolTargetFromConfig(target)
	}
	storedTargets, err := s.store.ListWOLTargets(ctx)
	if err != nil {
		return nil, err
	}
	for _, target := range storedTargets {
		target.Source = "user"
		byID[target.ID] = target
	}
	targets := make([]model.WOLTarget, 0, len(byID))
	for _, target := range byID {
		targets = append(targets, target)
	}
	sort.Slice(targets, func(i, j int) bool {
		left := strings.ToLower(targets[i].Name)
		right := strings.ToLower(targets[j].Name)
		if left == right {
			return targets[i].ID < targets[j].ID
		}
		return left < right
	})
	return targets, nil
}

func wolTargetFromConfig(target config.WOLTarget) model.WOLTarget {
	if target.UDPPort == 0 {
		target.UDPPort = 9
	}
	return model.WOLTarget{
		ID:          target.ID,
		Name:        target.Name,
		MAC:         target.MAC,
		IPAddress:   target.IPAddress,
		BroadcastIP: target.BroadcastIP,
		UDPPort:     target.UDPPort,
		Source:      "config",
	}
}

func healthMonitorFromConfig(monitor config.MonitorConfig) model.HealthMonitor {
	return model.HealthMonitor{
		ID:             monitor.ID,
		Name:           monitor.Name,
		Kind:           monitor.Kind,
		Host:           monitor.Host,
		Port:           monitor.Port,
		URL:            monitor.URL,
		TimeoutSeconds: monitor.TimeoutSeconds,
		Source:         "config",
	}
}

func normalizeHealthMonitorRequest(req model.HealthMonitorRequest, existing *model.HealthMonitor) (model.HealthMonitor, error) {
	monitor := model.HealthMonitor{}
	if existing != nil {
		monitor = *existing
	}
	monitor.ID = strings.TrimSpace(req.ID)
	if monitor.ID == "" {
		return model.HealthMonitor{}, errors.New("id is required")
	}
	if strings.Contains(monitor.ID, "/") {
		return model.HealthMonitor{}, errors.New("id cannot contain /")
	}
	if strings.TrimSpace(req.Name) != "" {
		monitor.Name = strings.TrimSpace(req.Name)
	}
	if monitor.Name == "" {
		return model.HealthMonitor{}, errors.New("name is required")
	}
	if strings.TrimSpace(req.Kind) != "" {
		monitor.Kind = strings.TrimSpace(req.Kind)
	} else if monitor.Kind == "" {
		if strings.TrimSpace(req.URL) != "" {
			monitor.Kind = "http"
		} else {
			monitor.Kind = "tcp"
		}
	}
	if strings.TrimSpace(req.Host) != "" {
		monitor.Host = strings.TrimSpace(req.Host)
	}
	if strings.TrimSpace(req.URL) != "" {
		monitor.URL = strings.TrimSpace(req.URL)
	}
	if req.Port != 0 {
		monitor.Port = req.Port
	}
	if req.TimeoutSeconds != 0 {
		monitor.TimeoutSeconds = req.TimeoutSeconds
	}
	if monitor.TimeoutSeconds <= 0 {
		monitor.TimeoutSeconds = 3
	}
	if monitor.TimeoutSeconds > 30 {
		return model.HealthMonitor{}, errors.New("timeout_seconds must be 30 or less")
	}
	switch monitor.Kind {
	case "tcp":
		monitor.URL = ""
		if monitor.Host == "" {
			return model.HealthMonitor{}, errors.New("host is required")
		}
		if monitor.Port == 0 {
			monitor.Port = 22
		}
		if monitor.Port < 1 || monitor.Port > 65535 {
			return model.HealthMonitor{}, errors.New("port must be between 1 and 65535")
		}
	case "http":
		monitor.Host = ""
		monitor.Port = 0
		if monitor.URL == "" {
			return model.HealthMonitor{}, errors.New("url is required")
		}
		if !strings.Contains(monitor.URL, "://") {
			monitor.URL = "http://" + monitor.URL
		}
		if _, err := url.ParseRequestURI(monitor.URL); err != nil {
			return model.HealthMonitor{}, fmt.Errorf("url: %w", err)
		}
	default:
		return model.HealthMonitor{}, errors.New("kind must be tcp or http")
	}
	return monitor, nil
}

func normalizeWOLTargetRequest(req model.WOLTargetRequest, existing *model.WOLTarget) (model.WOLTarget, error) {
	target := model.WOLTarget{}
	if existing != nil {
		target = *existing
	}
	target.ID = strings.TrimSpace(req.ID)
	if target.ID == "" {
		return model.WOLTarget{}, errors.New("id is required")
	}
	if strings.Contains(target.ID, "/") {
		return model.WOLTarget{}, errors.New("id cannot contain /")
	}
	if strings.TrimSpace(req.Name) != "" {
		target.Name = strings.TrimSpace(req.Name)
	}
	if target.Name == "" {
		return model.WOLTarget{}, errors.New("name is required")
	}
	if strings.TrimSpace(req.MAC) != "" {
		mac, err := net.ParseMAC(strings.TrimSpace(req.MAC))
		if err != nil {
			return model.WOLTarget{}, fmt.Errorf("mac: %w", err)
		}
		target.MAC = mac.String()
	}
	if target.MAC == "" {
		return model.WOLTarget{}, errors.New("mac is required")
	}
	if strings.TrimSpace(req.IPAddress) != "" {
		ip := net.ParseIP(strings.TrimSpace(req.IPAddress))
		if ip == nil || ip.To4() == nil {
			return model.WOLTarget{}, errors.New("ip_address must be an IPv4 address")
		}
		target.IPAddress = ip.To4().String()
	}
	if strings.TrimSpace(req.BroadcastIP) != "" {
		ip := net.ParseIP(strings.TrimSpace(req.BroadcastIP))
		if ip == nil || ip.To4() == nil {
			return model.WOLTarget{}, errors.New("broadcast_ip must be an IPv4 address")
		}
		target.BroadcastIP = ip.To4().String()
	}
	if target.BroadcastIP == "" && target.IPAddress != "" {
		subnetBits := req.SubnetBits
		if subnetBits == 0 {
			subnetBits = 24
		}
		broadcast, err := deriveIPv4Broadcast(target.IPAddress, subnetBits)
		if err != nil {
			return model.WOLTarget{}, err
		}
		target.BroadcastIP = broadcast
	}
	if target.BroadcastIP == "" {
		return model.WOLTarget{}, errors.New("broadcast_ip or ip_address is required")
	}
	if req.UDPPort != 0 {
		target.UDPPort = req.UDPPort
	}
	if target.UDPPort == 0 {
		target.UDPPort = 9
	}
	if target.UDPPort < 1 || target.UDPPort > 65535 {
		return model.WOLTarget{}, errors.New("udp_port must be between 1 and 65535")
	}
	return target, nil
}

func deriveIPv4Broadcast(ipAddress string, subnetBits int) (string, error) {
	if subnetBits < 1 || subnetBits > 32 {
		return "", errors.New("subnet_bits must be between 1 and 32")
	}
	ip := net.ParseIP(ipAddress).To4()
	if ip == nil {
		return "", errors.New("ip_address must be an IPv4 address")
	}
	mask := net.CIDRMask(subnetBits, 32)
	broadcast := make(net.IP, len(ip))
	for i := range ip {
		broadcast[i] = ip[i] | ^mask[i]
	}
	return broadcast.String(), nil
}

func statusRank(status string) int {
	switch status {
	case "down":
		return 0
	case "up":
		return 1
	default:
		return 2
	}
}

func validateSignedTime(created time.Time, subject string) error {
	age := time.Since(created)
	if age > signatureFreshnessWindow || age < -signatureFreshnessWindow {
		return fmt.Errorf("%s has expired", subject)
	}
	return nil
}

func (s *Server) recordDenied(ctx context.Context, env model.ActionEnvelope, reason string) {
	if env.ActionRunID == "" {
		env.ActionRunID = model.NewID("run")
	}
	record := model.ActionRecord{
		ActionRunID:   env.ActionRunID,
		EventID:       env.EventID,
		ActionID:      env.ActionID,
		ActorDeviceID: env.ActorDeviceID,
		Status:        "denied",
		ResultMessage: reason,
		CreatedAt:     time.Now().UTC(),
	}
	_, _ = s.store.UpsertAction(ctx, record)
}

func sourceSummary(src *config.SourceConfig) map[string]any {
	if src == nil {
		return map[string]any{}
	}
	return map[string]any{
		"method":      src.Method,
		"url":         src.URL,
		"json_path":   src.JSONPath,
		"format":      src.Format,
		"docker_host": src.DockerHost,
		"project":     src.Project,
	}
}

func opaqueEventPayload(bridgeID string, event model.Event) string {
	body, _ := json.Marshal(struct {
		BridgeID  string    `json:"bridge_id"`
		EventID   string    `json:"event_id"`
		CreatedAt time.Time `json:"created_at"`
		CardIDs   []string  `json:"card_ids,omitempty"`
	}{
		BridgeID:  bridgeID,
		EventID:   event.EventID,
		CreatedAt: event.CreatedAt,
		CardIDs:   event.CardIDs,
	})
	sum := sha256.Sum256(body)
	return base64.StdEncoding.EncodeToString(sum[:])
}

func withJSON(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		next.ServeHTTP(w, r)
	})
}

func decodeJSON(r *http.Request, dest any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(dest)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"error": err.Error()})
}
