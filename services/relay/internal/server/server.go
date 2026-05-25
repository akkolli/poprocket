package server

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/poprocket/poprocket/services/relay/internal/apns"
	"github.com/poprocket/poprocket/services/relay/internal/model"
	"github.com/poprocket/poprocket/services/relay/internal/store"
)

type Server struct {
	store    *store.Memory
	apns     apns.Client
	logger   *slog.Logger
	upgrader websocket.Upgrader
	started  time.Time
}

func New(memory *store.Memory, apnsClient apns.Client, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}
	return &Server{
		store:  memory,
		apns:   apnsClient,
		logger: logger,
		upgrader: websocket.Upgrader{
			CheckOrigin: func(r *http.Request) bool { return true },
		},
		started: time.Now().UTC(),
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", s.handleHealth)
	mux.HandleFunc("POST /v1/devices/register", s.handleRegisterDevice)
	mux.HandleFunc("POST /v1/push", s.handlePush)
	mux.HandleFunc("POST /v1/actions", s.handleAction)
	mux.HandleFunc("GET /v1/ws/bridge", s.handleBridgeWS)
	return withJSON(mux)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"started_at":     s.started,
		"server_time":    time.Now().UTC(),
		"uptime_seconds": int(time.Since(s.started).Seconds()),
	})
}

func (s *Server) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req model.DeviceRegistration
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.BridgeID == "" || req.DeviceID == "" || req.APNSToken == "" {
		writeError(w, http.StatusBadRequest, errors.New("bridge_id, device_id, and apns_token are required"))
		return
	}
	if req.Platform == "" {
		req.Platform = "ios"
	}
	device := s.store.RegisterDevice(req)
	writeJSON(w, http.StatusCreated, device)
}

func (s *Server) handlePush(w http.ResponseWriter, r *http.Request) {
	var req model.PushRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.BridgeID == "" || req.EventID == "" || req.EncryptedPayload == "" {
		writeError(w, http.StatusBadRequest, errors.New("bridge_id, event_id, and encrypted_payload are required"))
		return
	}
	devices := s.store.DevicesForPush(req.BridgeID, req.DeviceIDs)
	payload := apns.BuildPayload(req)
	deliveries := 0
	for _, device := range devices {
		if err := s.apns.Send(r.Context(), device.APNSToken, payload); err != nil {
			s.logger.WarnContext(r.Context(), "apns delivery failed", "bridge_id", req.BridgeID, "device_id", device.DeviceID, "event_id", req.EventID, "error", err)
			continue
		}
		deliveries++
	}
	writeJSON(w, http.StatusAccepted, model.PushResult{
		BridgeID:      req.BridgeID,
		EventID:       req.EventID,
		DeviceCount:   len(devices),
		DeliveryCount: deliveries,
	})
}

func (s *Server) handleAction(w http.ResponseWriter, r *http.Request) {
	var req model.ActionRelayRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.BridgeID == "" || req.ActionRunID == "" || len(req.Payload) == 0 {
		writeError(w, http.StatusBadRequest, errors.New("bridge_id, action_run_id, and payload are required"))
		return
	}
	if req.CreatedAt.IsZero() {
		req.CreatedAt = time.Now().UTC()
	}
	if req.Expired(time.Now().UTC()) {
		writeError(w, http.StatusGone, errors.New("action expired"))
		return
	}
	msg := model.BridgeMessage{Type: "action", Payload: req.Payload}
	if err := s.store.SendToBridge(req.BridgeID, msg); err != nil {
		status := http.StatusServiceUnavailable
		if !errors.Is(err, store.ErrBridgeOffline) {
			status = http.StatusBadGateway
		}
		writeError(w, status, err)
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"bridge_id":     req.BridgeID,
		"action_run_id": req.ActionRunID,
		"status":        "queued",
	})
}

func (s *Server) handleBridgeWS(w http.ResponseWriter, r *http.Request) {
	bridgeID := r.URL.Query().Get("bridge_id")
	if bridgeID == "" {
		writeError(w, http.StatusBadRequest, errors.New("bridge_id is required"))
		return
	}
	conn, err := s.upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	sender := &lockedConn{conn: conn}
	s.store.AttachBridge(bridgeID, sender)
	defer func() {
		s.store.DetachBridge(bridgeID, sender)
		conn.Close()
	}()

	for {
		var msg model.BridgeMessage
		if err := conn.ReadJSON(&msg); err != nil {
			s.logger.Info("bridge websocket closed", "bridge_id", bridgeID, "error", err)
			return
		}
		if msg.Type == "ping" {
			_ = sender.SendJSON(model.BridgeMessage{Type: "pong"})
		}
	}
}

type lockedConn struct {
	mu   sync.Mutex
	conn *websocket.Conn
}

func (c *lockedConn) SendJSON(v any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.conn.WriteJSON(v)
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
