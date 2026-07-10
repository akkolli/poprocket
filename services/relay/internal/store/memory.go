package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
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
	path    string
}

func NewMemory() *Memory {
	return &Memory{
		devices: map[string]map[string]model.Device{},
		bridges: map[string]BridgeSender{},
	}
}

func Open(path string) (*Memory, error) {
	memory := NewMemory()
	memory.path = path
	if path == "" {
		return memory, nil
	}
	body, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return memory, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read relay state: %w", err)
	}
	var persisted struct {
		Devices map[string]map[string]model.Device `json:"devices"`
	}
	if err := json.Unmarshal(body, &persisted); err != nil {
		return nil, fmt.Errorf("decode relay state: %w", err)
	}
	if persisted.Devices != nil {
		memory.devices = persisted.Devices
	}
	return memory, nil
}

func (m *Memory) RegisterDevice(reg model.DeviceRegistration) (model.Device, error) {
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
	previous, existed := m.devices[reg.BridgeID][reg.DeviceID]
	m.devices[reg.BridgeID][reg.DeviceID] = device
	if err := m.persistLocked(); err != nil {
		if existed {
			m.devices[reg.BridgeID][reg.DeviceID] = previous
		} else {
			delete(m.devices[reg.BridgeID], reg.DeviceID)
		}
		return model.Device{}, err
	}
	return device, nil
}

func (m *Memory) persistLocked() error {
	if m.path == "" {
		return nil
	}
	directory := filepath.Dir(m.path)
	if err := os.MkdirAll(directory, 0o700); err != nil {
		return fmt.Errorf("create relay state directory: %w", err)
	}
	body, err := json.Marshal(struct {
		Devices map[string]map[string]model.Device `json:"devices"`
	}{Devices: m.devices})
	if err != nil {
		return fmt.Errorf("encode relay state: %w", err)
	}
	temporary, err := os.CreateTemp(directory, ".relay-state-*")
	if err != nil {
		return fmt.Errorf("create relay state: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(body); err != nil {
		temporary.Close()
		return fmt.Errorf("write relay state: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return fmt.Errorf("sync relay state: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, m.path); err != nil {
		return fmt.Errorf("replace relay state: %w", err)
	}
	return nil
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
