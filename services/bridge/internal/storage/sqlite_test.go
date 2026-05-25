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
		Title:          "Backup failed",
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

func TestSQLiteActionAudit(t *testing.T) {
	store, err := OpenSQLite(filepath.Join(t.TempDir(), "poprocket.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()

	now := time.Unix(100, 0).UTC()
	created, err := store.UpsertAction(context.Background(), model.ActionRecord{
		ActionRunID:   "run_1",
		EventID:       "evt_1",
		ActionID:      "ack",
		ActorDeviceID: "iphone",
		Status:        "accepted",
		CreatedAt:     now,
	})
	if err != nil {
		t.Fatal(err)
	}
	if !created {
		t.Fatal("first UpsertAction created = false")
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
	if records[0].Status != "completed" || records[0].ResultMessage != "acknowledged" {
		t.Fatalf("record = %+v", records[0])
	}
}
