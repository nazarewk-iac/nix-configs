// Package ctl is the human and agent CLI against the manager's HTTP API.
package ctl

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// Client talks to the manager.
type Client struct {
	BaseURL string
	HTTP    *http.Client
}

// New returns a client with a sane timeout.
func New(baseURL string) *Client {
	return &Client{BaseURL: strings.TrimRight(baseURL, "/"), HTTP: &http.Client{Timeout: 30 * time.Second}}
}

func (c *Client) call(ctx context.Context, method, path string, body any) (map[string]any, error) {
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return nil, err
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.BaseURL+path, reader)
	if err != nil {
		return nil, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	payload, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("%s %s: %d %s", method, path, resp.StatusCode, strings.TrimSpace(string(payload)))
	}
	var out map[string]any
	if err := json.Unmarshal(payload, &out); err != nil {
		return nil, fmt.Errorf("%s %s: %w", method, path, err)
	}
	return out, nil
}

// Status is the manager's own view: profile, last switch, companions, in-flight count.
func (c *Client) Status(ctx context.Context) (map[string]any, error) {
	return c.call(ctx, http.MethodGet, "/status", nil)
}

// Stats aggregates the event journal.
func (c *Client) Stats(ctx context.Context) (map[string]any, error) {
	return c.call(ctx, http.MethodGet, "/stats", nil)
}

// Select switches, or reports the cost when dryRun is set.
func (c *Client) Select(ctx context.Context, profile string, dryRun bool) (map[string]any, error) {
	return c.call(ctx, http.MethodPost, "/select", map[string]any{"profile": profile, "dry_run": dryRun})
}

// Unload puts a companion away; an empty model unloads every companion.
func (c *Client) Unload(ctx context.Context, model string) (map[string]any, error) {
	return c.call(ctx, http.MethodPost, "/unload", map[string]any{"model": model})
}

// Events returns the newest journal records.
func (c *Client) Events(ctx context.Context, limit int) (map[string]any, error) {
	return c.call(ctx, http.MethodGet, fmt.Sprintf("/events?limit=%d", limit), nil)
}

// Run dispatches the CLI: up, down, status, stats, unload.
func Run(ctx context.Context, baseURL string, args []string, out io.Writer) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: ctl <up|down|status|stats|unload> [flags]")
	}
	client := New(baseURL)
	print := func(body map[string]any) error {
		raw, err := json.MarshalIndent(body, "", "  ")
		if err != nil {
			return err
		}
		_, err = fmt.Fprintln(out, string(raw))
		return err
	}

	switch args[0] {
	case "up":
		profile, ttl := "qfn", ""
		for i := 1; i < len(args); i++ {
			switch args[i] {
			case "--profile":
				i++
				if i < len(args) {
					profile = args[i]
				}
			case "--ttl":
				i++
				if i < len(args) {
					ttl = args[i]
				}
			}
		}
		body, err := client.Select(ctx, profile, false)
		if err != nil {
			return err
		}
		if err := print(body); err != nil {
			return err
		}
		if ttl == "" {
			return nil
		}
		if err := execRevert(ctx, revertCommand(baseURL, ttl)); err != nil {
			return err
		}
		_, err = fmt.Fprintf(out, "scheduled: revert to qfn-max in %s (unit strata-revert)\n", ttl)
		return err
	case "down":
		body, err := client.Select(ctx, "none", false)
		if err != nil {
			return err
		}
		return print(body)
	case "status":
		body, err := client.Status(ctx)
		if err != nil {
			return err
		}
		return print(body)
	case "stats":
		body, err := client.Stats(ctx)
		if err != nil {
			return err
		}
		return print(body)
	case "unload":
		model := ""
		for i := 1; i < len(args); i++ {
			if args[i] == "--model" && i+1 < len(args) {
				model = args[i+1]
				i++
			}
		}
		body, err := client.Unload(ctx, model)
		if err != nil {
			return err
		}
		return print(body)
	default:
		return fmt.Errorf("usage: ctl <up|down|status|stats|unload> [flags]; unknown %q", args[0])
	}
}

// revertCommand is the external timer that returns the engine to the resting profile. It lives
// outside the manager on purpose: a manager restart cannot drop it and a failing revert cannot hold
// the manager's lock (the failure mode of an in-process timer).
//
// It names `qfn-max`, not `qfn`: `qfn` is profile-neutral and would make the revert a no-op, and the
// resting default is the whole-card profile.
func revertCommand(baseURL, ttl string) []string {
	return []string{
		"sudo", "-n", "systemd-run", "--unit=strata-revert", "--on-active=" + ttl, "--collect",
		"--", "curl", "-sS", "-m", "900", "-X", "POST", baseURL + "/select",
		"-H", "Content-Type: application/json", "-d", `{"profile":"qfn-max"}`,
	}
}

// execRevert is a variable so a test can assert that `up` without --ttl never schedules anything.
var execRevert = func(ctx context.Context, argv []string) error {
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("scheduling the revert: %w: %s", err, string(output))
	}
	return nil
}
