// Package atuin reads Atuin Threads through the public CLI.
//
// The journal stores only the thread UUID and the message count; transcripts stay in Atuin's
// encrypted store. The package never opens Atuin's database.
package atuin

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ErrUnavailable reports that the atuin binary is not installed.
var ErrUnavailable = errors.New("atuin is not on PATH")

// Thread is one captured agent session.
type Thread struct {
	AtuinID      string `json:"atuin_id"`
	Harness      string `json:"harness"`
	SessionID    string `json:"session_id"`
	Cwd          string `json:"cwd"`
	Model        string `json:"model"`
	Title        string `json:"title"`
	StartedAt    string `json:"started_at"`
	UpdatedAt    string `json:"updated_at"`
	MessageCount int    `json:"message_count"`
}

// Runner is the Atuin surface the journal depends on. Tests replace it.
type Runner interface {
	// Available reports whether the atuin binary can be found.
	Available() bool
	List(ctx context.Context) ([]Thread, error)
	Show(ctx context.Context, id string) (Thread, error)
	Search(ctx context.Context, query, harness string, limit int) ([]Thread, error)
}

// CLI runs the real atuin binary.
type CLI struct {
	// Bin is the executable. Empty means "atuin" from PATH.
	Bin string
}

// Available reports whether the atuin binary can be found.
func (c *CLI) Available() bool {
	_, err := exec.LookPath(c.bin())
	return err == nil
}

func (c *CLI) bin() string {
	if c.Bin != "" {
		return c.Bin
	}
	return "atuin"
}

// List implements Runner.
func (c *CLI) List(ctx context.Context) ([]Thread, error) {
	out, err := c.run(ctx, "threads", "list", "--style", "json")
	if err != nil {
		return nil, err
	}
	return decodeThreads(out)
}

// Show implements Runner.
func (c *CLI) Show(ctx context.Context, id string) (Thread, error) {
	out, err := c.run(ctx, "threads", "show", id, "--style", "json")
	if err != nil {
		return Thread{}, err
	}
	var envelope struct {
		Session Thread `json:"session"`
	}
	if err := json.Unmarshal([]byte(out), &envelope); err != nil {
		return Thread{}, fmt.Errorf("parse atuin threads show output: %w", err)
	}
	return envelope.Session, nil
}

// Search implements Runner.
func (c *CLI) Search(ctx context.Context, query, harness string, limit int) ([]Thread, error) {
	args := []string{"threads", "search", query, "--style", "json"}
	if harness != "" {
		args = append(args, "--harness", harness)
	}
	if limit > 0 {
		args = append(args, "--limit", fmt.Sprint(limit))
	}
	out, err := c.run(ctx, args...)
	if err != nil {
		return nil, err
	}
	return decodeThreads(out)
}

func (c *CLI) run(ctx context.Context, args ...string) (string, error) {
	if _, err := exec.LookPath(c.bin()); err != nil {
		return "", ErrUnavailable
	}
	cmd := exec.CommandContext(ctx, c.bin(), args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		message := strings.TrimSpace(stderr.String())
		if message == "" {
			message = err.Error()
		}
		return "", fmt.Errorf("atuin %s: %s", args[1], message)
	}
	return stdout.String(), nil
}

func decodeThreads(out string) ([]Thread, error) {
	out = strings.TrimSpace(out)
	if out == "" || out == "null" {
		return nil, nil
	}
	var threads []Thread
	if err := json.Unmarshal([]byte(out), &threads); err != nil {
		return nil, fmt.Errorf("parse atuin threads output: %w", err)
	}
	return threads, nil
}

// Match kinds.
const (
	MatchSessionID = "session-id"
	MatchCwdTime   = "cwd-time"
	MatchTime      = "time-window"
	MatchNone      = "none"
	MatchAmbiguous = "ambiguous"
)

// Match is the result of linking a journal session to an Atuin thread.
type Match struct {
	Thread Thread
	How    string
}

// FindSession returns the thread whose agent session ID equals sessionID.
func FindSession(threads []Thread, sessionID string) (Thread, bool) {
	if sessionID == "" {
		return Thread{}, false
	}
	var exact []Thread
	for _, thread := range threads {
		if thread.SessionID == sessionID {
			exact = append(exact, thread)
		}
	}
	if len(exact) == 0 {
		return Thread{}, false
	}
	sort.SliceStable(exact, func(i, j int) bool { return exact[i].UpdatedAt > exact[j].UpdatedAt })
	return exact[0], true
}

// Find links a session to a thread. It tries the exact agent session ID first, then the same
// harness and cwd within window of started_at. Several remaining candidates are ambiguous: the
// caller must not guess.
func Find(threads []Thread, sessionID, harness, cwd string, started time.Time, window time.Duration) Match {
	if thread, ok := FindSession(threads, sessionID); ok {
		return Match{Thread: thread, How: MatchSessionID}
	}
	wantHarness := normalizeHarness(harness)
	wantCwd := ""
	if cwd != "" {
		wantCwd = filepath.Clean(cwd)
	}
	var near []Thread
	for _, thread := range threads {
		if normalizeHarness(thread.Harness) != wantHarness {
			continue
		}
		if wantCwd != "" && filepath.Clean(thread.Cwd) != wantCwd {
			continue
		}
		at, err := ParseTime(thread.StartedAt)
		if err != nil {
			continue
		}
		if window > 0 && absDuration(at.Sub(started)) > window {
			continue
		}
		near = append(near, thread)
	}
	switch len(near) {
	case 0:
		return Match{How: MatchNone}
	case 1:
		return Match{Thread: near[0], How: MatchCwdTime}
	default:
		return Match{How: MatchAmbiguous}
	}
}

// FindAt returns the thread whose [started_at, updated_at] interval covers at and whose cwd is
// cwd. It ignores the harness because a commit carries no harness. When several sessions overlap,
// the one that started last wins: it is the most recent work on that tree. Two sessions that
// started at the same instant are ambiguous.
func FindAt(threads []Thread, cwd string, at time.Time) Match {
	wantCwd := ""
	if cwd != "" {
		wantCwd = filepath.Clean(cwd)
	}
	type candidate struct {
		thread Thread
		start  time.Time
	}
	var candidates []candidate
	for _, thread := range threads {
		if wantCwd != "" && filepath.Clean(thread.Cwd) != wantCwd {
			continue
		}
		start, err := ParseTime(thread.StartedAt)
		if err != nil {
			continue
		}
		end, err := ParseTime(thread.UpdatedAt)
		if err != nil {
			continue
		}
		if at.Before(start) || at.After(end) {
			continue
		}
		candidates = append(candidates, candidate{thread: thread, start: start})
	}
	if len(candidates) == 0 {
		return Match{How: MatchNone}
	}
	sort.SliceStable(candidates, func(i, j int) bool { return candidates[i].start.After(candidates[j].start) })
	if len(candidates) > 1 && candidates[0].start.Equal(candidates[1].start) {
		return Match{How: MatchAmbiguous}
	}
	return Match{Thread: candidates[0].thread, How: MatchTime}
}

// ParseTime accepts the RFC3339 variants Atuin emits.
func ParseTime(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}, errors.New("empty timestamp")
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02 15:04:05.999999999 -07:00"} {
		if t, err := time.Parse(layout, value); err == nil {
			return t, nil
		}
	}
	return time.Time{}, fmt.Errorf("unrecognized timestamp %q", value)
}

func normalizeHarness(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	if strings.HasPrefix(name, "claude-code") {
		return "claude"
	}
	return name
}

func absDuration(d time.Duration) time.Duration {
	if d < 0 {
		return -d
	}
	return d
}

var _ Runner = (*CLI)(nil)
