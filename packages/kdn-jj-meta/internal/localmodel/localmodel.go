// Package localmodel records which locally served model produced a change.
//
// The fleet exposes stable names (`qfn`, `qwen3-omni`, `qwen-image-edit`) that resolve to a
// *profile* — a concrete pack, reserve and device layout (`max`, `omni-fast`, `image-qwen`). The
// same name can be served by a different profile an hour later, so a trailer that says only `qfn`
// is not a record of what ran: it is a record of which alias was typed.
//
// This package turns the alias into `alias=profile`, asking the manager which profile is current
// when the caller did not say. Nothing here is required: an unreachable manager degrades to the
// bare alias rather than failing a commit.
package localmodel

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// DefaultManagerURL is the profile manager on the serving host.
const DefaultManagerURL = "http://127.0.0.1:8181"

// Resolve normalises each value to `alias=profile`.
//
// Accepted forms:
//
//	qfn                 -> qfn=<profile the manager reports>
//	qfn=max             -> kept
//	qfn=max (weights)   -> kept
//
// A value that already names a profile is never rewritten, and a manager that cannot be reached
// leaves the alias alone: a trailer with less detail beats a commit that fails.
func Resolve(values []string, getenv func(string) string) []string {
	if getenv == nil {
		getenv = os.Getenv
	}
	var out []string
	profile, profileKnown := currentProfile(getenv)
	for _, raw := range values {
		value := strings.TrimSpace(raw)
		if value == "" {
			continue
		}
		if strings.Contains(value, "=") {
			out = append(out, value)
			continue
		}
		if profileKnown && profile != "" {
			out = append(out, fmt.Sprintf("%s=%s", value, profile))
			continue
		}
		out = append(out, value)
	}
	return out
}

// FromEnv reads the default list: `KDN_JJ_META_LOCAL_MODELS`, comma separated.
func FromEnv(getenv func(string) string) []string {
	if getenv == nil {
		getenv = os.Getenv
	}
	raw := strings.TrimSpace(getenv("KDN_JJ_META_LOCAL_MODELS"))
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// currentProfile asks the manager which profile is selected. The manager is the only component that
// knows: the alias is resolved by it, and the answer is what the card is actually serving.
func currentProfile(getenv func(string) string) (string, bool) {
	base := strings.TrimSpace(getenv("KDN_INFERENCE_MANAGER_URL"))
	if base == "" {
		base = DefaultManagerURL
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(strings.TrimRight(base, "/") + "/status")
	if err != nil {
		return "", false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", false
	}
	var status struct {
		Profile string `json:"profile"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
		return "", false
	}
	return strings.TrimSpace(status.Profile), true
}
