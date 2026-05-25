package store

import (
	"encoding/json"
	"testing"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

func TestDevicesForPush(t *testing.T) {
	mem := NewMemory()
	mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios1", Platform: "ios", APNSToken: "token1"})
	mem.RegisterDevice(model.DeviceRegistration{BridgeID: "bridge", DeviceID: "ios2", Platform: "ios", APNSToken: "token2"})

	if got := len(mem.DevicesForPush("bridge", nil)); got != 2 {
		t.Fatalf("all devices = %d", got)
	}
	if got := len(mem.DevicesForPush("bridge", []string{"ios2"})); got != 1 {
		t.Fatalf("filtered devices = %d", got)
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
