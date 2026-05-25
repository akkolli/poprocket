package store

import (
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/poprocket/poprocket/services/relay/internal/model"
)

var ErrBridgeOffline = errors.New("bridge offline")

type BridgeSender interface {
	SendJSON(v any) error
}

type Memory struct {
	mu      sync.RWMutex
	devices map[string]map[string]model.Device
	bridges map[string]BridgeSender
}

func NewMemory() *Memory {
	return &Memory{
		devices: map[string]map[string]model.Device{},
		bridges: map[string]BridgeSender{},
	}
}

func (m *Memory) RegisterDevice(reg model.DeviceRegistration) model.Device {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.devices[reg.BridgeID] == nil {
		m.devices[reg.BridgeID] = map[string]model.Device{}
	}
	device := model.Device{
		BridgeID:     reg.BridgeID,
		DeviceID:     reg.DeviceID,
		Platform:     reg.Platform,
		APNSToken:    reg.APNSToken,
		RegisteredAt: time.Now().UTC(),
	}
	m.devices[reg.BridgeID][reg.DeviceID] = device
	return device
}

func (m *Memory) DevicesForPush(bridgeID string, deviceIDs []string) []model.Device {
	m.mu.RLock()
	defer m.mu.RUnlock()
	byDevice := m.devices[bridgeID]
	if len(byDevice) == 0 {
		return nil
	}
	if len(deviceIDs) == 0 {
		devices := make([]model.Device, 0, len(byDevice))
		for _, device := range byDevice {
			devices = append(devices, device)
		}
		return devices
	}
	devices := make([]model.Device, 0, len(deviceIDs))
	for _, id := range deviceIDs {
		if device, ok := byDevice[id]; ok {
			devices = append(devices, device)
		}
	}
	return devices
}

func (m *Memory) AttachBridge(bridgeID string, sender BridgeSender) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.bridges[bridgeID] = sender
}

func (m *Memory) DetachBridge(bridgeID string, sender BridgeSender) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.bridges[bridgeID] == sender {
		delete(m.bridges, bridgeID)
	}
}

func (m *Memory) SendToBridge(bridgeID string, msg model.BridgeMessage) error {
	m.mu.RLock()
	sender := m.bridges[bridgeID]
	m.mu.RUnlock()
	if sender == nil {
		return ErrBridgeOffline
	}
	return sender.SendJSON(msg)
}

type MemoryBridgeSender struct {
	Messages []model.BridgeMessage
	Err      error
}

func (s *MemoryBridgeSender) SendJSON(v any) error {
	if s.Err != nil {
		return s.Err
	}
	body, err := json.Marshal(v)
	if err != nil {
		return err
	}
	var msg model.BridgeMessage
	if err := json.Unmarshal(body, &msg); err != nil {
		return err
	}
	s.Messages = append(s.Messages, msg)
	return nil
}
