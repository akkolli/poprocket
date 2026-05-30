package security

import (
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"testing"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/model"
)

func TestVerifyAction(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"wol:wake:target"}); err != nil {
		t.Fatal(err)
	}
	env := model.ActionEnvelope{
		ActionRunID:   "run_1",
		EventID:       "evt_1",
		ActionID:      "wol:target",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		CreatedAt:     time.Unix(100, 0).UTC(),
	}
	sig, err := SignAction(priv, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig

	if err := verifier.VerifyAction(env, []string{"wol:wake:target"}); err != nil {
		t.Fatalf("VerifyAction() error = %v", err)
	}

	env.ActionID = "tampered"
	if err := verifier.VerifyAction(env, []string{"wol:wake:target"}); !errors.Is(err, ErrBadSignature) {
		t.Fatalf("tampered VerifyAction() error = %v", err)
	}
}

func TestVerifySwiftActionVector(t *testing.T) {
	verifier := NewVerifier()
	const publicKey = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg="
	if err := verifier.RegisterDevice("iphone", publicKey, []string{"wol:wake:target"}); err != nil {
		t.Fatal(err)
	}
	env := model.ActionEnvelope{
		ActionRunID:   "run_1",
		EventID:       "evt_1",
		ActionID:      "wol:target",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		CreatedAt:     time.Unix(100, 0).UTC(),
		Signature:     "xLuG75L8JstRdEnN1tvcyG3SU7csSXOfpEc2Q3b6hoojafqHc7rEdgrJVm6FcBj1Ddo1PsfnniA+Blz9rrgvDw==",
	}

	message, err := CanonicalActionMessage(env)
	if err != nil {
		t.Fatal(err)
	}
	const expectedMessage = `{"action_run_id":"run_1","event_id":"evt_1","action_id":"wol:target","actor_device_id":"iphone","confirmed":true,"created_at":"1970-01-01T00:01:40Z"}`
	if string(message) != expectedMessage {
		t.Fatalf("CanonicalActionMessage() = %s", message)
	}
	if err := verifier.VerifyAction(env, []string{"wol:wake:target"}); err != nil {
		t.Fatalf("VerifyAction() error = %v", err)
	}
}

func TestCanonicalActionMessageIncludesParameters(t *testing.T) {
	env := model.ActionEnvelope{
		ActionRunID:   "run_1",
		ActionID:      "command:run",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		Parameters:    map[string]string{"command": "printf hello"},
		CreatedAt:     time.Unix(100, 0).UTC(),
	}

	message, err := CanonicalActionMessage(env)
	if err != nil {
		t.Fatal(err)
	}
	const expectedMessage = `{"action_run_id":"run_1","action_id":"command:run","actor_device_id":"iphone","confirmed":true,"parameters":{"command":"printf hello"},"created_at":"1970-01-01T00:01:40Z"}`
	if string(message) != expectedMessage {
		t.Fatalf("CanonicalActionMessage() = %s", message)
	}
}

func TestVerifyRequest(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"audit:read"}); err != nil {
		t.Fatal(err)
	}
	req := RequestSignature{
		Method:        "GET",
		Path:          "/v1/audit",
		Query:         "limit=8",
		ActorDeviceID: "iphone",
		CreatedAt:     "1970-01-01T00:01:40Z",
	}
	message, err := CanonicalRequestMessage(req)
	if err != nil {
		t.Fatal(err)
	}
	const expectedMessage = `{"method":"GET","path":"/v1/audit","query":"limit=8","actor_device_id":"iphone","created_at":"1970-01-01T00:01:40Z"}`
	if string(message) != expectedMessage {
		t.Fatalf("CanonicalRequestMessage() = %s", message)
	}
	sig, err := SignRequest(priv, req)
	if err != nil {
		t.Fatal(err)
	}
	req.Signature = sig

	if err := verifier.VerifyRequest(req, []string{"audit:read"}); err != nil {
		t.Fatalf("VerifyRequest() error = %v", err)
	}

	req.Query = "limit=99"
	if err := verifier.VerifyRequest(req, []string{"audit:read"}); !errors.Is(err, ErrBadSignature) {
		t.Fatalf("tampered VerifyRequest() error = %v", err)
	}
}

func TestVerifyActionDeniedScope(t *testing.T) {
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"cards:read"}); err != nil {
		t.Fatal(err)
	}
	env := model.ActionEnvelope{ActorDeviceID: "iphone"}
	if err := verifier.VerifyAction(env, []string{"wol:wake:target"}); !errors.Is(err, ErrDeniedScope) {
		t.Fatalf("VerifyAction() error = %v", err)
	}
}

func TestVerifyActionWildcardScope(t *testing.T) {
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	verifier := NewVerifier()
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"wol:wake:*"}); err != nil {
		t.Fatal(err)
	}
	env := model.ActionEnvelope{
		ActionRunID:   "run_1",
		ActionID:      "wol:target",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		CreatedAt:     time.Unix(100, 0).UTC(),
	}
	sig, err := SignAction(priv, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig
	if err := verifier.VerifyAction(env, []string{"wol:wake:target"}); err != nil {
		t.Fatalf("VerifyAction() error = %v", err)
	}
}
