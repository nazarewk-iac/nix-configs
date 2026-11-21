// Package status answers one question in one screen: what can this host serve, and what is
// serving right now.
//
// It is a view, not a control plane. Every configured fact comes from the deployment file and the
// placement policy; every live fact from something that already exists — the manager's /status,
// llama-swap's /running, /proc/meminfo, the card's sysfs, the engine's own log. A source that does
// not answer becomes a line of output rather than an error: whoever asks this question is usually
// looking at a host that has already gone wrong, and "the manager is unreachable" is part of the
// answer.
package status

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"kdn-inference-helpers/internal/policy"
)

// The three groups of the table. A profile serves chat, a companion sits beside one, and an image
// profile is a command of the same manager: the first two share the card with the engine, the last
// one replaces it.
const (
	GroupFrontier  = "frontier"
	GroupCompanion = "companion"
	GroupImage     = "image"
)

// Facts is what the placement policy measured about one model name. They are quoted, never
// recomputed: a table that guesses is worse than a table that admits it has no facts.
type Facts struct {
	VRAMMiB            int                `json:"vramMiB,omitempty"`
	KVReserveMiB       int                `json:"kvReserveMiB,omitempty"`
	LoadSeconds        int                `json:"loadSeconds,omitempty"`
	SwitchSeconds      int                `json:"switchSeconds,omitempty"`
	DecodeTps          float64            `json:"decodeTps,omitempty"`
	DecodeWithFrontier map[string]float64 `json:"decodeWithFrontier,omitempty"`
}

// VRAMTotalMiB is what the model takes on the card: weights plus the K/V it holds.
func (f Facts) VRAMTotalMiB() int { return f.VRAMMiB + f.KVReserveMiB }

// Profile is one row: a thing this host can serve, and the names and numbers that reach it.
type Profile struct {
	Name    string `json:"name"`
	Group   string `json:"group"`
	Pack    string `json:"pack,omitempty"`
	Context int    `json:"context,omitempty"`
	Slots   int    `json:"slots,omitempty"`
	// Aliases are the names a caller types. `qfn` is listed on the resting profile because it is
	// profile-neutral: it starts that one when nothing is loaded and never switches a running one.
	Aliases  []string `json:"aliases,omitempty"`
	Role     string   `json:"role"`
	Resting  bool     `json:"resting,omitempty"`
	Requires []string `json:"requiresProfile,omitempty"`
	Facts    *Facts   `json:"facts,omitempty"`
}

// EngineRow is what an engine adapter knows about one profile: the pack it loads, the window every
// slot is carved at, and how many slots decode at once.
type EngineRow struct {
	Pack    string
	Context int
	Slots   int
}

// Plan is the configured half of the answer: the profiles this deployment can serve.
type Plan struct {
	TextProfiles []string
	Commands     []string
	Aliases      map[string]string
	// Resting is where `qfn` lands with nothing loaded.
	Resting string
	// Colo are the profiles that keep a reserve for a companion.
	Colo []string
}

// FromDeployment builds the table from the deployment file, the engine adapter and the policy.
// A nil policy is a table without facts, which is exactly what a deployment that has not adopted
// the policy has.
func FromDeployment(p Plan, engine func(string) EngineRow, pol *policy.Policy) []Profile {
	models := map[string]policy.Model{}
	if pol != nil {
		models = pol.Models
	}
	// A policy names the llama-swap entry and the profile it runs (`qwen-image-edit` →
	// `image-qwen`); this is the only place the two vocabularies are joined.
	entry := map[string]string{}
	var companions []string
	for name, m := range models {
		if m.Profile != "" {
			entry[m.Profile] = name
		}
		if m.Tier == GroupCompanion {
			companions = append(companions, name)
		}
	}
	out := []Profile{}
	for _, name := range p.TextProfiles {
		row := engine(name)
		prof := Profile{
			Name: name, Group: GroupFrontier, Pack: row.Pack, Context: row.Context,
			Slots: row.Slots, Aliases: aliasesFor(name, p.Aliases, p.Resting), Role: role(name, p.Colo),
		}
		if prof.Resting = name == p.Resting; prof.Resting {
			prof.Role = "resting"
		}
		if named, ok := entry[name]; ok {
			prof.Facts = factsOf(models[named])
		}
		out = append(out, prof)
	}
	sort.Strings(companions)
	for _, name := range companions {
		m := models[name]
		out = append(out, Profile{
			Name: name, Group: GroupCompanion, Role: GroupCompanion,
			Aliases: []string{name}, Requires: m.RequiresProfile, Facts: factsOf(m),
		})
	}
	commands := append([]string(nil), p.Commands...)
	sort.Strings(commands)
	for _, name := range commands {
		prof := Profile{Name: name, Group: GroupImage, Role: GroupImage}
		if named, ok := entry[name]; ok {
			prof.Aliases = []string{named}
			prof.Facts = factsOf(models[named])
		}
		out = append(out, prof)
	}
	return out
}

// aliasesFor is every name that resolves to this profile. `qfn` is added to the resting one
// because it names no profile of its own.
func aliasesFor(name string, aliases map[string]string, resting string) []string {
	var out []string
	if name == resting {
		out = append(out, "qfn")
	}
	var named []string
	for alias, target := range aliases {
		if target == name {
			named = append(named, alias)
		}
	}
	sort.Strings(named)
	return append(out, named...)
}

// role is the one word that says what the profile is for. The policy's colo list is data; the
// shape words come from the profile name, which is where the deployment already states it, and
// they survive a missing policy.
func role(name string, colo []string) string {
	for _, c := range colo {
		if c == name {
			return "colo"
		}
	}
	for _, word := range []string{"colo", "omni", "long", "single", "swarm", "multi"} {
		if strings.Contains(name, word) {
			if word == "colo" || word == "omni" {
				return "colo"
			}
			return word
		}
	}
	return ""
}

// factsOf quotes a policy entry, and reports nothing when the entry carries no numbers: a zero is
// an unmeasured model, not a model that takes no VRAM.
func factsOf(m policy.Model) *Facts {
	f := Facts{
		VRAMMiB: m.VRAMMiB, KVReserveMiB: m.KVReserveMiB, LoadSeconds: m.LoadSeconds,
		SwitchSeconds: m.SwitchSeconds, DecodeTps: m.DecodeTps, DecodeWithFrontier: m.DecodeWithFrontier,
	}
	if f.VRAMMiB == 0 && f.KVReserveMiB == 0 {
		return nil
	}
	return &f
}

// PackName is the short pack label an operator reads: the adapter's base name, uppercased, with the
// repacker's prefix dropped (`unsloth-ud-iq4_xs` → `UD-IQ4_XS`).
func PackName(base string) string {
	return strings.ToUpper(strings.TrimPrefix(base, "unsloth-"))
}

// Manager is the manager's own view, or the reason it has none.
type Manager struct {
	URL                  string   `json:"url"`
	Reachable            bool     `json:"reachable"`
	Error                string   `json:"error,omitempty"`
	Profile              string   `json:"profile,omitempty"`
	Companions           []string `json:"companions"`
	InFlight             int      `json:"inFlight"`
	Draining             bool     `json:"draining"`
	EvictionID           string   `json:"evictionId,omitempty"`
	LastSwitch           *Switch  `json:"lastSwitch,omitempty"`
	LastSwitchSecondsAgo *int     `json:"lastSwitchSecondsAgo,omitempty"`
}

// Switch is the last profile transition the journal recorded.
type Switch struct {
	From    string `json:"from"`
	To      string `json:"to"`
	Seconds int    `json:"seconds"`
	Cause   string `json:"cause,omitempty"`
}

// Swap is llama-swap's view: the entries that are up right now.
type Swap struct {
	URL     string   `json:"url"`
	Running []string `json:"running"`
	Error   string   `json:"error,omitempty"`
}

// Free is the card and the host as they are now.
type Free struct {
	VRAMMiB      int `json:"vramMiB"`
	VRAMTotalMiB int `json:"vramTotalMiB"`
	RAMMiB       int `json:"ramMiB"`
	RAMTotalMiB  int `json:"ramTotalMiB"`
}

// PolicyInfo says which policy the facts came from, or why there are none.
type PolicyInfo struct {
	Path   string `json:"path"`
	Models int    `json:"models"`
	Error  string `json:"error,omitempty"`
}

// Snapshot is everything the command learned, in the shape both renderers read.
type Snapshot struct {
	Host     string    `json:"host"`
	Now      time.Time `json:"now"`
	Profiles []Profile `json:"profiles"`
	Manager  Manager   `json:"manager"`
	Swap     Swap      `json:"swap"`
	Free     Free      `json:"free"`
	// EngineRateTps is the engine's own last reported decode speed, when its log has one.
	EngineRateTps *float64 `json:"engineRateTps,omitempty"`
	// EngineRateAt is when the engine wrote that line.
	EngineRateAt *time.Time `json:"engineRateAt,omitempty"`
	Policy       PolicyInfo `json:"policy"`
}

// Loaded reports whether anything is serving. A `none` profile with no companion is an idle host,
// and an idle host has no live detail worth a screen.
func (s Snapshot) Loaded() bool {
	if s.Manager.Reachable && s.Manager.Profile != "" && s.Manager.Profile != "none" {
		return true
	}
	return len(s.Manager.Companions) > 0
}

// Row finds one profile of the table.
func (s Snapshot) Row(name string) *Profile {
	for i := range s.Profiles {
		if s.Profiles[i].Name == name {
			return &s.Profiles[i]
		}
	}
	return nil
}

// ---------------- live probes ----------------

// client is short on purpose: `status` is what an operator runs when something is wrong, and a
// wedged control plane must not hang the command that would say so.
var client = &http.Client{Timeout: 3 * time.Second}

func getJSON(ctx context.Context, url string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%d %s", resp.StatusCode, http.StatusText(resp.StatusCode))
	}
	return json.NewDecoder(resp.Body).Decode(out)
}

// ManagerView reads the manager's /status. A manager that does not answer is a fact to report, not
// a failure: the configured table is still the answer to most of the question.
func ManagerView(ctx context.Context, baseURL string) Manager {
	out := Manager{URL: baseURL, Companions: []string{}}
	var body struct {
		Profile    string   `json:"profile"`
		Companions []string `json:"loaded_companions"`
		InFlight   int      `json:"in_flight"`
		Draining   bool     `json:"draining"`
		EvictionID string   `json:"eviction_id"`
		LastSwitch *Switch  `json:"last_switch"`
		SecondsAgo *int     `json:"last_switch_seconds_ago"`
	}
	if err := getJSON(ctx, baseURL+"/status", &body); err != nil {
		out.Error = err.Error()
		return out
	}
	out.Reachable = true
	out.Profile, out.InFlight, out.Draining, out.EvictionID = body.Profile, body.InFlight, body.Draining, body.EvictionID
	out.LastSwitch, out.LastSwitchSecondsAgo = body.LastSwitch, body.SecondsAgo
	if body.Companions != nil {
		out.Companions = body.Companions
	}
	return out
}

// SwapView reads llama-swap's /running: the entries that are up. The manager owns the companions,
// so this is only about the entries themselves (`qfn`, an image editor).
func SwapView(ctx context.Context, baseURL string) Swap {
	out := Swap{URL: baseURL, Running: []string{}}
	var body struct {
		Running []struct {
			Model string `json:"model"`
		} `json:"running"`
	}
	if err := getJSON(ctx, baseURL+"/running", &body); err != nil {
		out.Error = err.Error()
		return out
	}
	for _, entry := range body.Running {
		if entry.Model != "" {
			out.Running = append(out.Running, entry.Model)
		}
	}
	return out
}

// VRAM reads the card that serves the models: the DRM device with the most VRAM. A host with an
// integrated GPU reports both, and the small one is never the one that holds a model.
func VRAM(root string) (freeMiB, totalMiB int, ok bool) {
	paths, _ := filepath.Glob(filepath.Join(root, "card[0-9]*", "device", "mem_info_vram_total"))
	best := 0
	for _, path := range paths {
		total, err := readInt(path)
		if err != nil || total <= best {
			continue
		}
		used, err := readInt(filepath.Join(filepath.Dir(path), "mem_info_vram_used"))
		if err != nil {
			continue
		}
		best = total
		totalMiB, freeMiB = total/1024/1024, (total-used)/1024/1024
	}
	return freeMiB, totalMiB, best > 0
}

// Memory reads MemTotal and MemAvailable from a meminfo-format file. MemAvailable, not MemFree:
// the page cache is what a model load is about to need, and the kernel already counts it as
// available.
func Memory(path string) (freeMiB, totalMiB int, ok bool) {
	body, err := os.ReadFile(path)
	if err != nil {
		return 0, 0, false
	}
	for _, line := range strings.Split(string(body), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		kb, err := strconv.Atoi(fields[1])
		if err != nil {
			continue
		}
		switch fields[0] {
		case "MemTotal:":
			totalMiB = kb / 1024
		case "MemAvailable:":
			freeMiB = kb / 1024
		}
	}
	return freeMiB, totalMiB, totalMiB > 0
}

// ratePattern is the engine's own report: `[strata] done: 31 tokens in 2 s (58.1 tok/s)`.
var ratePattern = regexp.MustCompile(`\(([0-9]+(?:\.[0-9]+)?) tok/s\)`)

// readyMarker is what the engine prints once a load has finished. A rate line above the newest
// marker belongs to an engine that has since been replaced: the log is appended across restarts, so
// the marker is the only thing that says which run a number came from.
const readyMarker = "ready: http"

// Rate is the engine's last reported decode speed and when it wrote it. The log is the only place
// the engine states a rate, so the tail is what is read: the whole file is gigabytes of loader
// output. The timestamp matters as much as the number — a rate from before the last switch belongs
// to an engine that no longer exists.
func Rate(path string) (float64, time.Time, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, time.Time{}, false
	}
	defer f.Close()
	const tail = 64 << 10
	info, err := f.Stat()
	if err != nil {
		return 0, time.Time{}, false
	}
	offset := info.Size() - tail
	if offset < 0 {
		offset = 0
	}
	buf := make([]byte, info.Size()-offset)
	if _, err := f.ReadAt(buf, offset); err != nil {
		return 0, time.Time{}, false
	}
	matches := ratePattern.FindAllSubmatchIndex(buf, -1)
	if len(matches) == 0 {
		return 0, time.Time{}, false
	}
	last := matches[len(matches)-1]
	if bytes.LastIndex(buf, []byte(readyMarker)) > last[0] {
		return 0, time.Time{}, false
	}
	value, err := strconv.ParseFloat(string(buf[last[2]:last[3]]), 64)
	if err != nil {
		return 0, time.Time{}, false
	}
	return value, info.ModTime(), true
}

func readInt(path string) (int, error) {
	body, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(strings.TrimSpace(string(body)))
}
