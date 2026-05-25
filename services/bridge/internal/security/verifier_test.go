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
	if err := verifier.RegisterDevice("iphone", base64.StdEncoding.EncodeToString(pub), []string{"wol:wake:nas"}); err != nil {
		t.Fatal(err)
	}
	env := model.ActionEnvelope{
		ActionRunID:   "run_1",
		EventID:       "evt_1",
		ActionID:      "wake_nas",
		ActorDeviceID: "iphone",
		Confirmed:     true,
		CreatedAt:     time.Unix(100, 0).UTC(),
	}
	sig, err := SignAction(priv, env)
	if err != nil {
		t.Fatal(err)
	}
	env.Signature = sig

	if err := verifier.VerifyAction(env, []string{"wol:wake:nas"}); err != nil {
		t.Fatalf("VerifyAction() error = %v", err)
	}

	env.ActionID = "tampered"
	if err := verifier.VerifyAction(env, []string{"wol:wake:nas"}); !errors.Is(err, ErrBadSignature) {
		t.Fatalf("tampered VerifyAction() error = %v", err)
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
	if err := verifier.VerifyAction(env, []string{"wol:wake:nas"}); !errors.Is(err, ErrDeniedScope) {
		t.Fatalf("VerifyAction() error = %v", err)
	}
}
