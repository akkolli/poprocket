package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/config"
	bridgerelay "github.com/poprocket/poprocket/services/bridge/internal/relay"
	"github.com/poprocket/poprocket/services/bridge/internal/security"
	"github.com/poprocket/poprocket/services/bridge/internal/server"
	"github.com/poprocket/poprocket/services/bridge/internal/storage"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfgPath := getenv("POPROCKET_BRIDGE_CONFIG", "bridge.yaml")
	cfg, err := config.LoadFile(cfgPath)
	if err != nil {
		logger.Error("load config", "error", err)
		os.Exit(1)
	}

	addr := getenv("POPROCKET_BRIDGE_ADDR", ":6567")
	store, err := storage.OpenSQLite(cfg.Bridge.DataPath)
	if err != nil {
		logger.Error("open sqlite", "error", err)
		os.Exit(1)
	}
	defer store.Close()

	verifier := security.NewVerifier()
	relayClient := bridgerelay.NewHTTPClient(cfg.Relay.URL, cfg.Relay.Token)
	app := server.New(cfg, store, verifier, relayClient, logger)
	runCtx, cancelRun := context.WithCancel(context.Background())
	defer cancelRun()
	if cfg.Relay.WebSocketURL != "" {
		wsClient := bridgerelay.BridgeWebSocketClient{
			URL:      cfg.Relay.WebSocketURL,
			BridgeID: cfg.Bridge.ID,
			Token:    cfg.Relay.Token,
		}
		go runBridgeWebSocket(runCtx, wsClient, app, logger)
	}

	httpServer := &http.Server{
		Addr:              addr,
		Handler:           app.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errs := make(chan error, 1)
	go func() {
		logger.Info("bridge listening", "addr", addr, "bridge_id", cfg.Bridge.ID)
		errs <- httpServer.ListenAndServe()
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case sig := <-stop:
		logger.Info("shutdown requested", "signal", sig.String())
		cancelRun()
	case err := <-errs:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("bridge stopped", "error", err)
			os.Exit(1)
		}
		cancelRun()
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		logger.Error("shutdown", "error", err)
		os.Exit(1)
	}
}

func runBridgeWebSocket(ctx context.Context, client bridgerelay.BridgeWebSocketClient, app *server.Server, logger *slog.Logger) {
	for ctx.Err() == nil {
		err := client.Run(ctx, func(ctx context.Context, msg bridgerelay.BridgeMessage) error {
			if msg.Type != "action" {
				return nil
			}
			var env server.RelayActionEnvelope
			if err := json.Unmarshal(msg.Payload, &env); err != nil {
				logger.WarnContext(ctx, "decode relay action", "error", err)
				return nil
			}
			result, status, err := app.ProcessAction(ctx, env.ActionEnvelope)
			if err != nil {
				logger.WarnContext(ctx, "relay action rejected", "action_run_id", env.ActionRunID, "status", status, "error", err)
				return nil
			}
			logger.InfoContext(ctx, "relay action processed", "action_run_id", result.ActionRunID, "status", result.Status, "duplicate", result.Duplicate)
			return nil
		})
		if ctx.Err() != nil {
			return
		}
		logger.Warn("relay websocket disconnected", "error", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(3 * time.Second):
		}
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
