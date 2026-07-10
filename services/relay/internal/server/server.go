package server

import (
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
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
	token    string
	started  time.Time
}

const maxJSONRequestBytes = 128 << 10

func New(memory *store.Memory, apnsClient apns.Client, token string, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}
	return &Server{
		store:  memory,
		apns:   apnsClient,
		logger: logger,
		token:  token,
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
	mux.HandleFunc("POST /v1/push", s.requireBearer(s.handlePush))
	mux.HandleFunc("POST /v1/actions", s.handleAction)
	mux.HandleFunc("GET /v1/ws/bridge", s.requireBearer(s.handleBridgeWS))
	return withJSON(mux)
}

func (s *Server) requireBearer(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !validBearerToken(r.Header.Get("Authorization"), s.token) {
			w.Header().Set("WWW-Authenticate", `Bearer realm="poprocket-relay"`)
			writeError(w, http.StatusUnauthorized, errors.New("relay authentication required"))
			return
		}
		next(w, r)
	}
}

func validBearerToken(header, expected string) bool {
	provided, ok := providedBearerToken(header)
	if !ok || expected == "" {
		return false
	}
	if len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}

func validDeviceBearerToken(header, secret, bridgeID string) bool {
	provided, ok := providedBearerToken(header)
	if !ok {
		return false
	}
	expected := relayDeviceAccessToken(secret, bridgeID)
	if expected == "" || len(provided) != len(expected) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}

func providedBearerToken(header string) (string, bool) {
	provided, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		return "", false
	}
	provided = strings.TrimSpace(provided)
	return provided, provided != ""
}

func relayDeviceAccessToken(secret, bridgeID string) string {
	if secret == "" || bridgeID == "" {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte("poprocket-device:" + bridgeID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
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
	if !validDeviceBearerToken(r.Header.Get("Authorization"), s.token, req.BridgeID) {
		w.Header().Set("WWW-Authenticate", `Bearer realm="poprocket-relay-device"`)
		writeError(w, http.StatusUnauthorized, errors.New("relay device authentication required"))
		return
	}
	if err := validateIdentifier("bridge_id", req.BridgeID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateIdentifier("device_id", req.DeviceID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if len(req.APNSToken) > 512 {
		writeError(w, http.StatusBadRequest, errors.New("apns_token is too long"))
		return
	}
	if decoded, err := hex.DecodeString(req.APNSToken); err != nil || len(decoded) == 0 {
		writeError(w, http.StatusBadRequest, errors.New("apns_token must be non-empty hexadecimal bytes"))
		return
	}
	if req.Platform == "" {
		req.Platform = "ios"
	}
	if req.Platform != "ios" {
		writeError(w, http.StatusBadRequest, errors.New("platform must be ios"))
		return
	}
	device, err := s.store.RegisterDevice(req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("store device registration"))
		return
	}
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
	if err := validateIdentifier("bridge_id", req.BridgeID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateIdentifier("event_id", req.EventID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.TTLSeconds < 1 || req.TTLSeconds > 86400 {
		writeError(w, http.StatusBadRequest, errors.New("ttl_seconds must be between 1 and 86400"))
		return
	}
	if req.CreatedAt.IsZero() {
		req.CreatedAt = time.Now().UTC()
	}
	now := time.Now().UTC()
	if req.CreatedAt.After(now.Add(5 * time.Minute)) {
		writeError(w, http.StatusBadRequest, errors.New("created_at is too far in the future"))
		return
	}
	if now.After(req.CreatedAt.Add(time.Duration(req.TTLSeconds) * time.Second)) {
		writeError(w, http.StatusGone, errors.New("push expired"))
		return
	}
	devices := s.store.DevicesForPush(req.BridgeID, req.DeviceIDs)
	payload := apns.BuildPayload(req)
	deliveryOptions := apns.DeliveryOptions{
		Expiration: req.CreatedAt.Add(time.Duration(req.TTLSeconds) * time.Second),
		CollapseID: req.EventID,
	}
	deliveries := 0
	for _, device := range devices {
		if err := s.apns.Send(r.Context(), device.APNSToken, payload, deliveryOptions); err != nil {
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
	if !validDeviceBearerToken(r.Header.Get("Authorization"), s.token, req.BridgeID) {
		w.Header().Set("WWW-Authenticate", `Bearer realm="poprocket-relay-device"`)
		writeError(w, http.StatusUnauthorized, errors.New("relay device authentication required"))
		return
	}
	if err := validateIdentifier("bridge_id", req.BridgeID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := validateIdentifier("action_run_id", req.ActionRunID); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.CreatedAt.IsZero() {
		writeError(w, http.StatusBadRequest, errors.New("created_at is required"))
		return
	}
	if req.TTLSeconds < 1 || req.TTLSeconds > 300 {
		writeError(w, http.StatusBadRequest, errors.New("ttl_seconds must be between 1 and 300"))
		return
	}
	now := time.Now().UTC()
	if req.CreatedAt.After(now.Add(5 * time.Minute)) {
		writeError(w, http.StatusBadRequest, errors.New("created_at is too far in the future"))
		return
	}
	if req.Expired(now) {
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
	if err := validateIdentifier("bridge_id", bridgeID); err != nil {
		writeError(w, http.StatusBadRequest, err)
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

func validateIdentifier(name, value string) error {
	if len(value) < 1 || len(value) > 128 {
		return fmt.Errorf("%s must be between 1 and 128 characters", name)
	}
	for _, char := range value {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') {
			continue
		}
		switch char {
		case '-', '_', '.', ':':
			continue
		default:
			return fmt.Errorf("%s contains unsupported characters", name)
		}
	}
	return nil
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
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		if r.ContentLength > maxJSONRequestBytes {
			writeError(w, http.StatusRequestEntityTooLarge, errors.New("request body is too large"))
			return
		}
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, maxJSONRequestBytes)
		}
		next.ServeHTTP(w, r)
	})
}

func decodeJSON(r *http.Request, dest any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dest); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("request body must contain one JSON object")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"error": err.Error()})
}
