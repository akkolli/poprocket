package security

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"

	"github.com/poprocket/poprocket/services/bridge/internal/model"
)

var (
	ErrUnknownDevice = errors.New("unknown device")
	ErrBadSignature  = errors.New("bad signature")
	ErrDeniedScope   = errors.New("denied scope")
)

type Device struct {
	ID        string
	PublicKey ed25519.PublicKey
	Scopes    map[string]struct{}
}

type RequestSignature struct {
	Method        string
	Path          string
	Query         string
	ActorDeviceID string
	CreatedAt     string
	Signature     string
}

type Verifier struct {
	mu      sync.RWMutex
	devices map[string]Device
}

func NewVerifier() *Verifier {
	return &Verifier{devices: map[string]Device{}}
}

func (v *Verifier) RegisterDevice(id, publicKeyBase64 string, scopes []string) error {
	if id == "" {
		return errors.New("device id is required")
	}
	key, err := base64.StdEncoding.DecodeString(publicKeyBase64)
	if err != nil {
		return fmt.Errorf("decode public key: %w", err)
	}
	if len(key) != ed25519.PublicKeySize {
		return fmt.Errorf("public key must be %d bytes, got %d", ed25519.PublicKeySize, len(key))
	}
	scopeSet := map[string]struct{}{}
	for _, scope := range scopes {
		scopeSet[scope] = struct{}{}
	}
	v.mu.Lock()
	defer v.mu.Unlock()
	v.devices[id] = Device{ID: id, PublicKey: ed25519.PublicKey(key), Scopes: scopeSet}
	return nil
}

func (v *Verifier) VerifyAction(env model.ActionEnvelope, requiredScopes []string) error {
	v.mu.RLock()
	device, ok := v.devices[env.ActorDeviceID]
	v.mu.RUnlock()
	if !ok {
		return ErrUnknownDevice
	}
	if !hasScopes(device.Scopes, requiredScopes) {
		return ErrDeniedScope
	}
	message, err := CanonicalActionMessage(env)
	if err != nil {
		return err
	}
	sig, err := base64.StdEncoding.DecodeString(env.Signature)
	if err != nil {
		return fmt.Errorf("decode signature: %w", err)
	}
	if !ed25519.Verify(device.PublicKey, message, sig) {
		return ErrBadSignature
	}
	return nil
}

func (v *Verifier) VerifyRequest(req RequestSignature, requiredScopes []string) error {
	v.mu.RLock()
	device, ok := v.devices[req.ActorDeviceID]
	v.mu.RUnlock()
	if !ok {
		return ErrUnknownDevice
	}
	if !hasScopes(device.Scopes, requiredScopes) {
		return ErrDeniedScope
	}
	message, err := CanonicalRequestMessage(req)
	if err != nil {
		return err
	}
	sig, err := base64.StdEncoding.DecodeString(req.Signature)
	if err != nil {
		return fmt.Errorf("decode signature: %w", err)
	}
	if !ed25519.Verify(device.PublicKey, message, sig) {
		return ErrBadSignature
	}
	return nil
}

func CanonicalActionMessage(env model.ActionEnvelope) ([]byte, error) {
	body := struct {
		ActionRunID    string            `json:"action_run_id"`
		EventID        string            `json:"event_id,omitempty"`
		ActionID       string            `json:"action_id"`
		ActorDeviceID  string            `json:"actor_device_id"`
		IdempotencyKey string            `json:"idempotency_key,omitempty"`
		Confirmed      bool              `json:"confirmed,omitempty"`
		Parameters     map[string]string `json:"parameters,omitempty"`
		CreatedAt      string            `json:"created_at"`
	}{
		ActionRunID:    env.ActionRunID,
		EventID:        env.EventID,
		ActionID:       env.ActionID,
		ActorDeviceID:  env.ActorDeviceID,
		IdempotencyKey: env.IdempotencyKey,
		Confirmed:      env.Confirmed,
		Parameters:     env.Parameters,
		CreatedAt:      env.CreatedAt.UTC().Format("2006-01-02T15:04:05.999999999Z07:00"),
	}
	return json.Marshal(body)
}

func SignAction(privateKey ed25519.PrivateKey, env model.ActionEnvelope) (string, error) {
	message, err := CanonicalActionMessage(env)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, message)), nil
}

func CanonicalRequestMessage(req RequestSignature) ([]byte, error) {
	body := struct {
		Method        string `json:"method"`
		Path          string `json:"path"`
		Query         string `json:"query,omitempty"`
		ActorDeviceID string `json:"actor_device_id"`
		CreatedAt     string `json:"created_at"`
	}{
		Method:        req.Method,
		Path:          req.Path,
		Query:         req.Query,
		ActorDeviceID: req.ActorDeviceID,
		CreatedAt:     req.CreatedAt,
	}
	return json.Marshal(body)
}

func SignRequest(privateKey ed25519.PrivateKey, req RequestSignature) (string, error) {
	message, err := CanonicalRequestMessage(req)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(ed25519.Sign(privateKey, message)), nil
}

func hasScopes(actual map[string]struct{}, required []string) bool {
	for _, scope := range required {
		if !hasScope(actual, scope) {
			return false
		}
	}
	return true
}

func hasScope(actual map[string]struct{}, required string) bool {
	if _, ok := actual[required]; ok {
		return true
	}
	for granted := range actual {
		prefix, ok := strings.CutSuffix(granted, "*")
		if ok && strings.HasPrefix(required, prefix) {
			return true
		}
	}
	return false
}
