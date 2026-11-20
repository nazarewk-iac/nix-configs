// Package swap is the llama-swap client: which models are loaded, and unloading one by name.
//
// llama-swap owns the companion processes, so this is the only way the runtime can see them. It is
// also the `/unload` path: putting a companion away frees its VRAM without touching the engine.
package swap

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client talks to llama-swap.
type Client struct {
	BaseURL string
	HTTP    *http.Client
}

// New returns a client with a sane timeout. The base URL is llama-swap's root, not `/v1`.
func New(baseURL string) *Client {
	return &Client{BaseURL: strings.TrimRight(baseURL, "/"), HTTP: &http.Client{Timeout: 30 * time.Second}}
}

// model is the shape `/v1/models` returns.
type model struct {
	ID     string `json:"id"`
	Status struct {
		Value string `json:"value"`
	} `json:"status"`
}

// Loaded lists the model ids llama-swap reports as loaded, aliases included.
func (c *Client) Loaded(ctx context.Context) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.BaseURL+"/v1/models", nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return nil, fmt.Errorf("llama-swap %s: %d %s", "/v1/models", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var payload struct {
		Data []model `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return nil, fmt.Errorf("llama-swap /v1/models: %w", err)
	}
	var loaded []string
	for _, m := range payload.Data {
		if m.Status.Value == "loaded" {
			loaded = append(loaded, m.ID)
		}
	}
	return loaded, nil
}

// Unload stops one model process. With an empty name llama-swap unloads everything, which the
// manager never wants: that would kill the frontier proxies whose requests it is holding.
func (c *Client) Unload(ctx context.Context, model string) error {
	target := c.BaseURL + "/api/models/unload"
	if model != "" {
		target += "/" + url.PathEscape(model)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, target, nil)
	if err != nil {
		return err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("llama-swap unload %q: %d %s", model, resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}
