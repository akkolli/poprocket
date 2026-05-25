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
	"net/http"
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
	writeJSON(w, http.StatusCreated, map[string]any{
		"device_id": req.DeviceID,
		"scopes":    scopes,
	})
}

func (s *Server) handleCards(w http.ResponseWriter, r *http.Request) {
	now := time.Now().UTC()
	reader := adapters.Reader{}
	cards := []model.CardSnapshot{{
		ID:                "bridge_host",
		Title:             "Bridge Host",
		Kind:              "host_status",
		Status:            "fresh",
		UpdatedAt:         now,
		StaleAfterSeconds: 120,
		Value: map[string]any{
			"bridge_id":        s.cfg.Bridge.ID,
			"relay_configured": s.cfg.Relay.URL != "",
			"uptime_seconds":   int(time.Since(s.started).Seconds()),
		},
	}}
	for _, card := range s.cfg.Cards {
		if card.ID == "bridge_host" {
			continue
		}
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
	if env.CreatedAt.IsZero() {
		env.CreatedAt = time.Now().UTC()
	}
	action, ok := s.cfg.FindAction(env.ActionID)
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

	status, resultMessage := s.executeAction(ctx, action)
	if err := s.store.CompleteAction(ctx, env.ActionRunID, status, resultMessage, time.Now().UTC()); err != nil {
		return ActionResult{}, http.StatusInternalServerError, err
	}
	return ActionResult{ActionRunID: env.ActionRunID, Status: status, ResultMessage: resultMessage}, http.StatusAccepted, nil
}

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	records, err := s.store.ListActions(r.Context(), limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"actions": records})
}

func (s *Server) handleWOL(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/wol/")
	targetID, ok := strings.CutSuffix(path, "/wake")
	if !ok || targetID == "" {
		writeError(w, http.StatusBadRequest, errors.New("expected /v1/wol/{target_id}/wake"))
		return
	}
	target, ok := s.cfg.FindWOLTarget(targetID)
	if !ok {
		writeError(w, http.StatusNotFound, fmt.Errorf("wol target %s not found", targetID))
		return
	}
	runID := model.NewID("run")
	record := model.ActionRecord{
		ActionRunID:   runID,
		ActionID:      "wol:" + targetID,
		ActorDeviceID: "bridge-http",
		Status:        "accepted",
		CreatedAt:     time.Now().UTC(),
	}
	_, _ = s.store.UpsertAction(r.Context(), record)
	status, result := "completed", "magic packet sent"
	if err := wol.Send(r.Context(), target.MAC, target.BroadcastIP, target.UDPPort); err != nil {
		status, result = "failed", err.Error()
	}
	_ = s.store.CompleteAction(r.Context(), runID, status, result, time.Now().UTC())
	writeJSON(w, http.StatusAccepted, map[string]any{
		"action_run_id":  runID,
		"target_id":      targetID,
		"status":         status,
		"result_message": result,
	})
}

func (s *Server) executeAction(ctx context.Context, action config.ActionConfig) (string, string) {
	switch action.Kind {
	case "audit":
		return "completed", "acknowledged"
	case "wol":
		target, ok := s.cfg.FindWOLTarget(action.TargetID)
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
	default:
		return "failed", "unsupported action kind"
	}
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
