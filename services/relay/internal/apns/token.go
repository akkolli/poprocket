package apns

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	maxAPNSPayloadBytes = 4096
	providerTokenMaxAge = 50 * time.Minute
)

type TokenConfig struct {
	TeamID        string
	KeyID         string
	Topic         string
	PrivateKeyPEM []byte
	Sandbox       bool
	Endpoint      string
	HTTPClient    *http.Client
	Now           func() time.Time
}

type TokenClient struct {
	teamID   string
	keyID    string
	topic    string
	key      *ecdsa.PrivateKey
	endpoint string
	client   *http.Client
	now      func() time.Time

	mu       sync.Mutex
	token    string
	issuedAt time.Time
}

func NewTokenClient(cfg TokenConfig) (*TokenClient, error) {
	if strings.TrimSpace(cfg.TeamID) == "" || strings.TrimSpace(cfg.KeyID) == "" || strings.TrimSpace(cfg.Topic) == "" {
		return nil, errors.New("APNs team ID, key ID, and topic are required")
	}
	key, err := parseAPNSPrivateKey(cfg.PrivateKeyPEM)
	if err != nil {
		return nil, err
	}
	endpoint := strings.TrimRight(cfg.Endpoint, "/")
	if endpoint == "" {
		if cfg.Sandbox {
			endpoint = "https://api.sandbox.push.apple.com"
		} else {
			endpoint = "https://api.push.apple.com"
		}
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{
			Timeout: 15 * time.Second,
			Transport: &http.Transport{
				ForceAttemptHTTP2: true,
				TLSClientConfig:   &tls.Config{MinVersion: tls.VersionTLS12},
			},
		}
	}
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	return &TokenClient{
		teamID:   strings.TrimSpace(cfg.TeamID),
		keyID:    strings.TrimSpace(cfg.KeyID),
		topic:    strings.TrimSpace(cfg.Topic),
		key:      key,
		endpoint: endpoint,
		client:   client,
		now:      now,
	}, nil
}

func (c *TokenClient) Send(ctx context.Context, deviceToken string, payload Payload, options DeliveryOptions) error {
	deviceToken = strings.TrimSpace(deviceToken)
	decodedToken, err := hex.DecodeString(deviceToken)
	if err != nil || len(decodedToken) == 0 {
		return errors.New("APNs device token must be non-empty hexadecimal bytes")
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode APNs payload: %w", err)
	}
	if len(body) > maxAPNSPayloadBytes {
		return fmt.Errorf("APNs payload is %d bytes; maximum is %d", len(body), maxAPNSPayloadBytes)
	}
	providerToken, err := c.providerToken()
	if err != nil {
		return err
	}
	requestURL := c.endpoint + "/3/device/" + url.PathEscape(deviceToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, requestURL, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "bearer "+providerToken)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apns-topic", c.topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", "10")
	if !options.Expiration.IsZero() {
		req.Header.Set("apns-expiration", fmt.Sprintf("%d", options.Expiration.UTC().Unix()))
	}
	if collapseID := strings.TrimSpace(options.CollapseID); collapseID != "" && len(collapseID) <= 64 {
		req.Header.Set("apns-collapse-id", collapseID)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("send APNs request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusOK {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		return nil
	}
	var response struct {
		Reason string `json:"reason"`
	}
	_ = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&response)
	if response.Reason == "" {
		response.Reason = http.StatusText(resp.StatusCode)
	}
	return fmt.Errorf("APNs rejected notification with status %d: %s", resp.StatusCode, response.Reason)
}

func (c *TokenClient) providerToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := c.now().UTC()
	if c.token != "" && now.Sub(c.issuedAt) < providerTokenMaxAge && now.Sub(c.issuedAt) >= 0 {
		return c.token, nil
	}
	header, err := json.Marshal(map[string]string{"alg": "ES256", "kid": c.keyID})
	if err != nil {
		return "", err
	}
	claims, err := json.Marshal(map[string]any{"iss": c.teamID, "iat": now.Unix()})
	if err != nil {
		return "", err
	}
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(claims)
	digest := sha256.Sum256([]byte(unsigned))
	r, s, err := ecdsa.Sign(rand.Reader, c.key, digest[:])
	if err != nil {
		return "", fmt.Errorf("sign APNs provider token: %w", err)
	}
	signature := make([]byte, 64)
	writePaddedInteger(signature[:32], r)
	writePaddedInteger(signature[32:], s)
	c.token = unsigned + "." + base64.RawURLEncoding.EncodeToString(signature)
	c.issuedAt = now
	return c.token, nil
}

func parseAPNSPrivateKey(value []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(value)
	if block == nil {
		return nil, errors.New("decode APNs private key PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse APNs private key: %w", err)
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, errors.New("APNs private key must be an ECDSA P-256 PKCS#8 key")
	}
	return key, nil
}

func writePaddedInteger(destination []byte, value *big.Int) {
	encoded := value.Bytes()
	copy(destination[len(destination)-len(encoded):], encoded)
}
