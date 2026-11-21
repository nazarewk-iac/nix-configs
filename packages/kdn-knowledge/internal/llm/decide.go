package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// DecideTimeout is the placement-manager budget. The manager answers on the host itself, so a
// slow answer means "unknown", not "refuse".
const DecideTimeout = 5 * time.Second

// WhyNode is one node of the decision trace.
type WhyNode struct {
	Node   string         `json:"node"`
	Type   string         `json:"type"`
	Verb   string         `json:"verb"`
	Result string         `json:"result"`
	Note   string         `json:"note,omitempty"`
	Facts  map[string]any `json:"facts,omitempty"`
}

// Verdict is the answer of POST /decide.
type Verdict struct {
	Verdict string    `json:"verdict"`
	Why     []WhyNode `json:"why"`
	Raw     string    `json:"-"`
}

// Admits reports whether the manager would load the model.
func (v *Verdict) Admits() bool { return v.Verdict == "admit" }

// Summary is one line: the verdict and the first failing check.
func (v *Verdict) Summary() string {
	if v.Verdict == "" {
		return "unknown"
	}
	for _, node := range v.Why {
		if node.Type == "check" && node.Result == "failure" {
			if node.Verb != "" {
				return v.Verdict + ": " + node.Verb
			}
			return v.Verdict
		}
	}
	return v.Verdict
}

// Trace renders the failing checks, at most max of them, so a refusal is legible in a terminal.
func (v *Verdict) Trace(max int) []string {
	lines := make([]string, 0, max)
	for _, node := range v.Why {
		if node.Type != "check" || node.Result != "failure" {
			continue
		}
		line := node.Verb
		if facts, err := json.Marshal(node.Facts); err == nil && len(node.Facts) > 0 {
			line += " " + string(facts)
		}
		lines = append(lines, line)
		if len(lines) >= max {
			break
		}
	}
	if len(lines) == 0 {
		for _, node := range v.Why {
			lines = append(lines, node.Node+" "+node.Type+" "+node.Result)
			if len(lines) >= max {
				break
			}
		}
	}
	return lines
}

// Decide asks the placement manager whether the model may load. The manager is reachable from
// the fleet host only; a connection error is "unknown", not a refusal.
func Decide(ctx context.Context, managerURL, model string) (*Verdict, error) {
	managerURL = strings.TrimRight(strings.TrimSpace(managerURL), "/")
	if managerURL == "" {
		return nil, fmt.Errorf("no placement manager configured")
	}
	body, err := json.Marshal(map[string]any{"model": model})
	if err != nil {
		return nil, err
	}
	client := &http.Client{Timeout: DecideTimeout}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, managerURL+"/decide", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = response.Body.Close()
	}()
	raw, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if response.StatusCode == http.StatusTooManyRequests {
		return nil, &CooldownError{Body: strings.TrimSpace(string(raw))}
	}
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("placement manager answered %d: %s", response.StatusCode, strings.TrimSpace(string(raw)))
	}
	var verdict Verdict
	if err := json.Unmarshal(raw, &verdict); err != nil {
		return nil, fmt.Errorf("placement manager returned invalid JSON: %w", err)
	}
	verdict.Raw = string(raw)
	return &verdict, nil
}

// CooldownError is the manager's 429: a switch just happened and the next one has to wait for
// the cooldown. It is not a capacity refusal, so the caller continues with "unknown".
type CooldownError struct {
	Body string
}

func (e *CooldownError) Error() string {
	if strings.TrimSpace(e.Body) == "" {
		return "placement manager is in its post-switch cooldown (429); retry shortly"
	}
	return "placement manager is in its post-switch cooldown (429): " + e.Body
}
