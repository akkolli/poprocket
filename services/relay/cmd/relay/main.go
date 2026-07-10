package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/poprocket/poprocket/services/relay/internal/apns"
	"github.com/poprocket/poprocket/services/relay/internal/server"
	"github.com/poprocket/poprocket/services/relay/internal/store"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	addr := getenv("POPROCKET_RELAY_ADDR", ":8081")
	token := os.Getenv("POPROCKET_RELAY_TOKEN")
	if token == "" {
		logger.Error("POPROCKET_RELAY_TOKEN is required")
		os.Exit(1)
	}

	apnsClient, err := configuredAPNSClient(logger)
	if err != nil {
		logger.Error("configure APNs", "error", err)
		os.Exit(1)
	}
	relayStore, err := store.Open(os.Getenv("POPROCKET_RELAY_DATA_PATH"))
	if err != nil {
		logger.Error("open relay state", "error", err)
		os.Exit(1)
	}
	app := server.New(relayStore, apnsClient, token, logger)
	httpServer := &http.Server{
		Addr:              addr,
		Handler:           app.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}

	errs := make(chan error, 1)
	go func() {
		logger.Info("relay listening", "addr", addr)
		errs <- httpServer.ListenAndServe()
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	select {
	case sig := <-stop:
		logger.Info("shutdown requested", "signal", sig.String())
	case err := <-errs:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("relay stopped", "error", err)
			os.Exit(1)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		logger.Error("shutdown", "error", err)
		os.Exit(1)
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func configuredAPNSClient(logger *slog.Logger) (apns.Client, error) {
	switch mode := strings.ToLower(strings.TrimSpace(getenv("POPROCKET_APNS_MODE", "log"))); mode {
	case "log":
		return apns.NewLogClient(logger), nil
	case "token":
		keyPath := os.Getenv("POPROCKET_APNS_PRIVATE_KEY_PATH")
		if keyPath == "" {
			return nil, errors.New("POPROCKET_APNS_PRIVATE_KEY_PATH is required in token mode")
		}
		privateKey, err := os.ReadFile(keyPath)
		if err != nil {
			return nil, fmt.Errorf("read APNs private key: %w", err)
		}
		sandbox, err := strconv.ParseBool(getenv("POPROCKET_APNS_SANDBOX", "false"))
		if err != nil {
			return nil, fmt.Errorf("POPROCKET_APNS_SANDBOX: %w", err)
		}
		return apns.NewTokenClient(apns.TokenConfig{
			TeamID:        os.Getenv("POPROCKET_APNS_TEAM_ID"),
			KeyID:         os.Getenv("POPROCKET_APNS_KEY_ID"),
			Topic:         os.Getenv("POPROCKET_APNS_TOPIC"),
			PrivateKeyPEM: privateKey,
			Sandbox:       sandbox,
		})
	default:
		return nil, fmt.Errorf("unsupported POPROCKET_APNS_MODE %q", mode)
	}
}
