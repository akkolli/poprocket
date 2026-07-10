package adapters

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/poprocket/poprocket/services/bridge/internal/config"
)

const maxCardResponseBytes = 1 << 20

type Reader struct {
	Client         *http.Client
	SecretResolver SecretResolver
}

type SecretResolver func(name string) (string, bool)

func (r Reader) ReadCard(ctx context.Context, card config.CardConfig) (any, error) {
	switch card.Kind {
	case "generic_rest", "uptime_kuma_status_page":
		return r.readREST(ctx, card)
	case "docker_compose":
		if card.Source == nil {
			return nil, fmt.Errorf("card %s source is required", card.ID)
		}
		return ReadDockerCompose(ctx, card.Source.DockerHost, card.Source.Project)
	default:
		return map[string]any{"configured": true}, nil
	}
}

func (r Reader) readREST(ctx context.Context, card config.CardConfig) (any, error) {
	if card.Source == nil {
		return nil, fmt.Errorf("card %s source is required", card.ID)
	}
	method := card.Source.Method
	if method == "" {
		method = http.MethodGet
	}
	if strings.ToUpper(method) != http.MethodGet {
		return nil, fmt.Errorf("card %s only GET sources are supported in v1", card.ID)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, card.Source.URL, nil)
	if err != nil {
		return nil, err
	}
	resolver := r.SecretResolver
	if resolver == nil {
		resolver = EnvSecretResolver
	}
	for header, secretName := range card.Source.HeadersFromSecrets {
		value, ok := resolver(secretName)
		if !ok {
			return nil, fmt.Errorf("secret %s is not configured", secretName)
		}
		req.Header.Set(header, value)
	}
	client := r.Client
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("source returned %s", resp.Status)
	}
	limited := &io.LimitedReader{R: resp.Body, N: maxCardResponseBytes + 1}
	var body any
	if err := json.NewDecoder(limited).Decode(&body); err != nil {
		return nil, err
	}
	if limited.N <= 0 {
		return nil, fmt.Errorf("source response exceeds %d bytes", maxCardResponseBytes)
	}
	if card.Source.JSONPath == "" {
		return body, nil
	}
	selected, ok := SelectJSONPath(body, card.Source.JSONPath)
	if !ok {
		return nil, fmt.Errorf("json path %s not found", card.Source.JSONPath)
	}
	return selected, nil
}

func EnvSecretResolver(name string) (string, bool) {
	envName := "POPROCKET_SECRET_" + strings.ToUpper(strings.NewReplacer("-", "_", ".", "_").Replace(name))
	return os.LookupEnv(envName)
}
