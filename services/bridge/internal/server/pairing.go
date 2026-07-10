package server

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/model"
	"github.com/poprocket/poprocket/services/bridge/internal/security"
)

func (s *Server) handlePairingStart(w http.ResponseWriter, r *http.Request) {
	if token := strings.TrimSpace(s.cfg.Security.PairingAccessToken); token != "" && !validBearerToken(r.Header.Get("Authorization"), token) {
		w.Header().Set("WWW-Authenticate", `Bearer realm="poprocket-bridge-pairing"`)
		writeError(w, http.StatusUnauthorized, errors.New("pairing access token required"))
		return
	}
	token := model.NewID("pair")
	now := time.Now().UTC()
	expiresAt := now.Add(time.Duration(s.cfg.Security.PairingTTLSeconds) * time.Second)
	s.mu.Lock()
	for sessionToken, sessionExpiry := range s.sessions {
		if !sessionExpiry.After(now) {
			delete(s.sessions, sessionToken)
		}
	}
	if len(s.sessions) >= maxPairingSessions {
		s.mu.Unlock()
		writeError(w, http.StatusTooManyRequests, errors.New("too many active pairing sessions; wait for an existing session to expire"))
		return
	}
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
	scopes := grantedPairingScopes(req.Scopes, s.cfg.Security.DefaultScopes)
	if err := security.ValidatePublicKey(req.PublicKey); err != nil {
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
	if err := s.verifier.RegisterDevice(req.DeviceID, req.PublicKey, scopes); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, model.PairingCompleteResponse{
		DeviceID:           req.DeviceID,
		Scopes:             scopes,
		PairingAccessToken: s.cfg.Security.PairingAccessToken,
		RelayAccessToken:   relayDeviceAccessToken(s.cfg.Relay.Token, s.cfg.Bridge.ID),
	})
}

func grantedPairingScopes(requested, allowed []string) []string {
	if len(requested) == 0 {
		requested = allowed
	}
	granted := make([]string, 0, len(requested))
	seen := make(map[string]struct{}, len(requested))
	for _, scope := range requested {
		scope = strings.TrimSpace(scope)
		if scope == "" || !scopeGrantAllowed(scope, allowed) {
			continue
		}
		if _, exists := seen[scope]; exists {
			continue
		}
		seen[scope] = struct{}{}
		granted = append(granted, scope)
	}
	return granted
}

func scopeGrantAllowed(requested string, allowed []string) bool {
	for _, candidate := range allowed {
		candidate = strings.TrimSpace(candidate)
		if requested == candidate {
			return true
		}
		prefix, wildcard := strings.CutSuffix(candidate, "*")
		if wildcard && !strings.HasSuffix(requested, "*") && strings.HasPrefix(requested, prefix) {
			return true
		}
	}
	return false
}

func relayDeviceAccessToken(secret, bridgeID string) string {
	if secret == "" || bridgeID == "" {
		return ""
	}
	mac := hmac.New(sha256.New, []byte(secret))
	_, _ = mac.Write([]byte("poprocket-device:" + bridgeID))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}
