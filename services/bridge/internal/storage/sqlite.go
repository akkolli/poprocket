package storage

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/model"
	_ "modernc.org/sqlite"
)

type Store interface {
	SaveEvent(ctx context.Context, event model.Event) (bool, error)
	UpsertAction(ctx context.Context, record model.ActionRecord) (bool, error)
	CompleteAction(ctx context.Context, actionRunID, status, resultMessage string, completedAt time.Time) error
	ListActions(ctx context.Context, limit int) ([]model.ActionRecord, error)
	ListWOLTargets(ctx context.Context) ([]model.WOLTarget, error)
	SaveWOLTarget(ctx context.Context, target model.WOLTarget) error
	DeleteWOLTarget(ctx context.Context, id string) error
	Close() error
}

type SQLiteStore struct {
	db *sql.DB
}

func OpenSQLite(path string) (*SQLiteStore, error) {
	if path == "" {
		return nil, errors.New("sqlite path is required")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	store := &SQLiteStore{db: db}
	if err := store.migrate(context.Background()); err != nil {
		db.Close()
		return nil, err
	}
	return store, nil
}

func (s *SQLiteStore) Close() error {
	return s.db.Close()
}

func (s *SQLiteStore) migrate(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx, `
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS events (
  event_id TEXT PRIMARY KEY,
  idempotency_key TEXT UNIQUE,
  payload_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS action_audit (
  action_run_id TEXT PRIMARY KEY,
  event_id TEXT,
  action_id TEXT NOT NULL,
  actor_device_id TEXT NOT NULL,
  status TEXT NOT NULL,
  result_message TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_action_audit_created_at ON action_audit(created_at DESC);
CREATE TABLE IF NOT EXISTS wol_targets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mac TEXT NOT NULL,
  ip_address TEXT,
  broadcast_ip TEXT NOT NULL,
  udp_port INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_wol_targets_name ON wol_targets(name);
`)
	return err
}

func (s *SQLiteStore) SaveEvent(ctx context.Context, event model.Event) (bool, error) {
	payload, err := json.Marshal(event)
	if err != nil {
		return false, err
	}
	var idem any
	if event.IdempotencyKey != "" {
		idem = event.IdempotencyKey
	}
	res, err := s.db.ExecContext(ctx, `
INSERT OR IGNORE INTO events (event_id, idempotency_key, payload_json, created_at)
VALUES (?, ?, ?, ?)`,
		event.EventID,
		idem,
		string(payload),
		event.CreatedAt.UTC().Format(time.RFC3339Nano),
	)
	if err != nil {
		return false, err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	return rows == 1, nil
}

func (s *SQLiteStore) UpsertAction(ctx context.Context, record model.ActionRecord) (bool, error) {
	var completed any
	if record.CompletedAt != nil {
		completed = record.CompletedAt.UTC().Format(time.RFC3339Nano)
	}
	res, err := s.db.ExecContext(ctx, `
INSERT OR IGNORE INTO action_audit (
  action_run_id, event_id, action_id, actor_device_id, status, result_message, created_at, completed_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		record.ActionRunID,
		record.EventID,
		record.ActionID,
		record.ActorDeviceID,
		record.Status,
		record.ResultMessage,
		record.CreatedAt.UTC().Format(time.RFC3339Nano),
		completed,
	)
	if err != nil {
		return false, err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return false, err
	}
	return rows == 1, nil
}

func (s *SQLiteStore) CompleteAction(ctx context.Context, actionRunID, status, resultMessage string, completedAt time.Time) error {
	res, err := s.db.ExecContext(ctx, `
UPDATE action_audit
SET status = ?, result_message = ?, completed_at = ?
WHERE action_run_id = ?`,
		status,
		resultMessage,
		completedAt.UTC().Format(time.RFC3339Nano),
		actionRunID,
	)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return fmt.Errorf("action_run_id %s not found", actionRunID)
	}
	return nil
}

func (s *SQLiteStore) ListActions(ctx context.Context, limit int) ([]model.ActionRecord, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx, `
SELECT action_run_id, event_id, action_id, actor_device_id, status, result_message, created_at, completed_at
FROM action_audit
ORDER BY created_at DESC
LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var records []model.ActionRecord
	for rows.Next() {
		var record model.ActionRecord
		var created, completed sql.NullString
		if err := rows.Scan(
			&record.ActionRunID,
			&record.EventID,
			&record.ActionID,
			&record.ActorDeviceID,
			&record.Status,
			&record.ResultMessage,
			&created,
			&completed,
		); err != nil {
			return nil, err
		}
		if created.Valid {
			record.CreatedAt, _ = time.Parse(time.RFC3339Nano, created.String)
		}
		if completed.Valid {
			t, _ := time.Parse(time.RFC3339Nano, completed.String)
			record.CompletedAt = &t
		}
		records = append(records, record)
	}
	return records, rows.Err()
}

func (s *SQLiteStore) ListWOLTargets(ctx context.Context) ([]model.WOLTarget, error) {
	rows, err := s.db.QueryContext(ctx, `
SELECT id, name, mac, ip_address, broadcast_ip, udp_port, created_at, updated_at
FROM wol_targets
ORDER BY lower(name), id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var targets []model.WOLTarget
	for rows.Next() {
		var target model.WOLTarget
		var ipAddress sql.NullString
		var created, updated string
		if err := rows.Scan(
			&target.ID,
			&target.Name,
			&target.MAC,
			&ipAddress,
			&target.BroadcastIP,
			&target.UDPPort,
			&created,
			&updated,
		); err != nil {
			return nil, err
		}
		if ipAddress.Valid {
			target.IPAddress = ipAddress.String
		}
		if parsed, err := time.Parse(time.RFC3339Nano, created); err == nil {
			target.CreatedAt = &parsed
		}
		if parsed, err := time.Parse(time.RFC3339Nano, updated); err == nil {
			target.UpdatedAt = &parsed
		}
		targets = append(targets, target)
	}
	return targets, rows.Err()
}

func (s *SQLiteStore) SaveWOLTarget(ctx context.Context, target model.WOLTarget) error {
	_, err := s.db.ExecContext(ctx, `
INSERT INTO wol_targets (
  id, name, mac, ip_address, broadcast_ip, udp_port, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  name = excluded.name,
  mac = excluded.mac,
  ip_address = excluded.ip_address,
  broadcast_ip = excluded.broadcast_ip,
  udp_port = excluded.udp_port,
  updated_at = excluded.updated_at`,
		target.ID,
		target.Name,
		target.MAC,
		nullString(target.IPAddress),
		target.BroadcastIP,
		target.UDPPort,
		formatOptionalTime(target.CreatedAt),
		formatOptionalTime(target.UpdatedAt),
	)
	return err
}

func (s *SQLiteStore) DeleteWOLTarget(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM wol_targets WHERE id = ?`, id)
	return err
}

func nullString(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func formatOptionalTime(value *time.Time) string {
	if value == nil {
		return time.Now().UTC().Format(time.RFC3339Nano)
	}
	return value.UTC().Format(time.RFC3339Nano)
}
