package adapters

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type dockerContainer struct {
	ID     string            `json:"Id"`
	Names  []string          `json:"Names"`
	Image  string            `json:"Image"`
	State  string            `json:"State"`
	Status string            `json:"Status"`
	Labels map[string]string `json:"Labels"`
}

func ReadDockerCompose(ctx context.Context, dockerHost, project string) (any, error) {
	client, baseURL, err := dockerClient(dockerHost)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/containers/json?all=1", nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("docker returned %s", resp.Status)
	}
	var containers []dockerContainer
	if err := json.NewDecoder(resp.Body).Decode(&containers); err != nil {
		return nil, err
	}
	filtered := make([]map[string]any, 0, len(containers))
	running := 0
	for _, container := range containers {
		if project != "" && container.Labels["com.docker.compose.project"] != project {
			continue
		}
		if container.State == "running" {
			running++
		}
		filtered = append(filtered, map[string]any{
			"id":      shortID(container.ID),
			"name":    firstName(container.Names),
			"image":   container.Image,
			"state":   container.State,
			"status":  container.Status,
			"service": container.Labels["com.docker.compose.service"],
		})
	}
	return map[string]any{
		"project":    project,
		"running":    running,
		"total":      len(filtered),
		"containers": filtered,
	}, nil
}

func RunDockerContainerAction(ctx context.Context, dockerHost, containerID, operation string) error {
	switch operation {
	case "start", "stop", "restart":
	default:
		return fmt.Errorf("unsupported docker operation %q", operation)
	}
	if containerID == "" {
		return fmt.Errorf("container target_id is required")
	}
	client, baseURL, err := dockerClient(dockerHost)
	if err != nil {
		return err
	}
	pathID := url.PathEscape(containerID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, baseURL+"/containers/"+pathID+"/"+operation, bytes.NewReader(nil))
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("docker %s returned %s", operation, resp.Status)
	}
	return nil
}

func dockerClient(dockerHost string) (*http.Client, string, error) {
	if dockerHost == "" {
		dockerHost = "unix:///var/run/docker.sock"
	}
	u, err := url.Parse(dockerHost)
	if err != nil {
		return nil, "", err
	}
	switch u.Scheme {
	case "unix":
		socketPath := u.Path
		if socketPath == "" {
			return nil, "", fmt.Errorf("unix docker host path is required")
		}
		transport := &http.Transport{
			DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
				dialer := net.Dialer{Timeout: 5 * time.Second}
				return dialer.DialContext(ctx, "unix", socketPath)
			},
		}
		return &http.Client{Transport: transport, Timeout: 10 * time.Second}, "http://docker", nil
	case "http", "https":
		return &http.Client{Timeout: 10 * time.Second}, strings.TrimRight(dockerHost, "/"), nil
	default:
		return nil, "", fmt.Errorf("unsupported docker host scheme %q", u.Scheme)
	}
}

func shortID(id string) string {
	if len(id) <= 12 {
		return id
	}
	return id[:12]
}

func firstName(names []string) string {
	if len(names) == 0 {
		return ""
	}
	return strings.TrimPrefix(names[0], "/")
}
