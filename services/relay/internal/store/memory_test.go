package store

import (
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

func TestDevicesForPush(t *testing.T) {
	mem := NewMemory()
	if _, err := mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios1", Platform: "ios", APNSToken: "token1"}); err != nil {
		t.Fatal(err)
	}
	if _, err := mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios2", Platform: "ios", APNSToken: "token2"}); err != nil {
		t.Fatal(err)
	}

	if got := len(mem.DevicesForPush("bridge", nil)); got != 2 {
		t.Fatalf("all devices = %d", got)
	}
	if got := len(mem.DevicesForPush("bridge", []string{"ios2"})); got != 1 {
		t.Fatalf("filtered devices = %d", got)
	}
}

func TestDeviceRegistrationsPersistAcrossOpen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "relay-state.json")
	first, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := first.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios", Platform: "ios", APNSToken: "token"}); err != nil {
		t.Fatal(err)
	}

	second, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	devices := second.DevicesForPush("bridge", nil)
	if len(devices) != 1 || devices[0].APNSToken != "token" {
		t.Fatalf("devices = %+v", devices)
	}
}

func TestSendToBridge(t *testing.T) {
	mem := NewMemory()
	sender := &MemoryBridgeSender{}
	mem.AttachBridge("bridge", sender)
	payload := json.RawMessage(`{"action_run_id":"run_1"}`)
	if err := mem.SendToBridge("bridge", model.BridgeMessage{Type: "action", Payload: payload}); err != nil {
		t.Fatal(err)
	}
	if got := len(sender.Messages); got != 1 {
		t.Fatalf("messages = %d", got)
	}
	if sender.Messages[0].Type != "action" {
		t.Fatalf("message = %+v", sender.Messages[0])
	}
}
