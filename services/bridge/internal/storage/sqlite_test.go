package storage

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/model"
)

func TestSQLiteEventIdempotency(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	event := model.Event{
		EventID:        "evt_1",
		Title:          "Job failed",
		IdempotencyKey: "backup-1",
		CreatedAt:      time.Unix(100, 0).UTC(),
	}
	created, err := store.SaveEvent(context.Background(), event)
	if err != nil {
		t.Fatal(err)
	}
	if !created {
		t.Fatal("first SaveEvent created = false")
	}
	event.EventID = "evt_2"
	created, err = store.SaveEvent(context.Background(), event)
	if err != nil {
		t.Fatal(err)
	}
	if created {
		t.Fatal("duplicate SaveEvent created = true")
	}
}

func TestSQLiteDeviceRegistration(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	now := time.Unix(100, 0).UTC()
	if err := store.SaveDevice(context.Background(), model.DeviceRegistration{
		ID:        "iphone",
		PublicKey: "public-key",
		Scopes:    []string{"cards:read", "command:run"},
		CreatedAt: now,
		UpdatedAt: now,
	}); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveDevice(context.Background(), model.DeviceRegistration{
		ID:        "iphone",
		PublicKey: "public-key-2",
		Scopes:    []string{"cards:read"},
		CreatedAt: now.Add(time.Hour),
		UpdatedAt: now.Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}

	devices, err := store.ListDevices(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(devices); got != 1 {
		t.Fatalf("len(devices) = %d", got)
	}
	if devices[0].ID != "iphone" || devices[0].PublicKey != "public-key-2" {
		t.Fatalf("device = %+v", devices[0])
	}
	if got := devices[0].Scopes; len(got) != 1 || got[0] != "cards:read" {
		t.Fatalf("scopes = %+v", got)
	}
	if !devices[0].CreatedAt.Equal(now) {
		t.Fatalf("created_at = %s", devices[0].CreatedAt)
	}
}

func TestSQLiteActionAudit(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	now := time.Unix(100, 0).UTC()
	created, err := store.UpsertAction(context.Background(), model.ActionRecord{
		ActionRunID:    "run_1",
		EventID:        "evt_1",
		ActionID:       "ack",
		ActorDeviceID:  "iphone",
		IdempotencyKey: "evt_1:ack",
		Status:         "accepted",
		CreatedAt:      now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !created {
		t.Fatal("first UpsertAction created = false")
	}
	duplicate, err := store.UpsertAction(context.Background(), model.ActionRecord{
		ActionRunID:    "run_2",
		EventID:        "evt_1",
		ActionID:       "ack",
		ActorDeviceID:  "iphone",
		IdempotencyKey: "evt_1:ack",
		Status:         "accepted",
		CreatedAt:      now.Add(time.Second),
	})
	if err != nil {
		t.Fatal(err)
	}
	if duplicate {
		t.Fatal("duplicate idempotency key created a second action")
	}
	if err := store.CompleteAction(context.Background(), "run_1", "completed", "acknowledged", now.Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	records, err := store.ListActions(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	if got := len(records); got != 1 {
		t.Fatalf("len(records) = %d", got)
	}
	if records[0].Status != "completed" || records[0].ResultMessage != "acknowledged" || records[0].IdempotencyKey != "evt_1:ack" {
		t.Fatalf("record = %+v", records[0])
	}
}

func TestSQLiteWOLTargets(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	now := time.Unix(100, 0).UTC()
	target := model.WOLTarget{
		ID:          "target",
		Name:        "Target",
		MAC:         "02:00:5e:10:00:01",
		IPAddress:   "192.168.1.50",
		BroadcastIP: "192.168.1.255",
		UDPPort:     9,
		CreatedAt:   &now,
		UpdatedAt:   &now,
	}
	if err := store.SaveWOLTarget(context.Background(), target); err != nil {
		t.Fatal(err)
	}
	target.Name = "Storage"
	if err := store.SaveWOLTarget(context.Background(), target); err != nil {
		t.Fatal(err)
	}
	targets, err := store.ListWOLTargets(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(targets); got != 1 {
		t.Fatalf("len(targets) = %d", got)
	}
	if targets[0].Name != "Storage" || targets[0].BroadcastIP != "192.168.1.255" {
		t.Fatalf("target = %+v", targets[0])
	}
	if err := store.DeleteWOLTarget(context.Background(), "target"); err != nil {
		t.Fatal(err)
	}
	targets, err = store.ListWOLTargets(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(targets) != 0 {
		t.Fatalf("targets after delete = %+v", targets)
	}
}

func TestSQLiteHealthMonitorsAndState(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	now := time.Unix(100, 0).UTC()
	monitor := model.HealthMonitor{
		ID:             "ssh",
		Name:           "SSH",
		Kind:           "tcp",
		Host:           "server",
		Port:           22,
		TimeoutSeconds: 3,
		CreatedAt:      &now,
		UpdatedAt:      &now,
	}
	if err := store.SaveHealthMonitor(context.Background(), monitor); err != nil {
		t.Fatal(err)
	}
	monitor.Name = "Server SSH"
	if err := store.SaveHealthMonitor(context.Background(), monitor); err != nil {
		t.Fatal(err)
	}
	monitors, err := store.ListHealthMonitors(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if got := len(monitors); got != 1 {
		t.Fatalf("len(monitors) = %d", got)
	}
	if monitors[0].Name != "Server SSH" || monitors[0].Host != "server" || monitors[0].Port != 22 {
		t.Fatalf("monitor = %+v", monitors[0])
	}
	state := model.HealthMonitorState{
		ID:              "ssh",
		Status:          "up",
		CheckedAt:       now.Add(time.Minute),
		StatusChangedAt: now,
	}
	if err := store.SaveHealthMonitorState(context.Background(), state); err != nil {
		t.Fatal(err)
	}
	gotState, ok, err := store.GetHealthMonitorState(context.Background(), "ssh")
	if err != nil {
		t.Fatal(err)
	}
	if !ok || gotState.Status != "up" || !gotState.StatusChangedAt.Equal(now) {
		t.Fatalf("state = %+v ok = %v", gotState, ok)
	}
	if err := store.DeleteHealthMonitor(context.Background(), "ssh"); err != nil {
		t.Fatal(err)
	}
	monitors, err = store.ListHealthMonitors(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(monitors) != 0 {
		t.Fatalf("monitors after delete = %+v", monitors)
	}
	if _, ok, err := store.GetHealthMonitorState(context.Background(), "ssh"); err != nil || ok {
		t.Fatalf("state after delete ok = %v err = %v", ok, err)
	}
}
