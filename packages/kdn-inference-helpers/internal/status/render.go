package status

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

// Render writes the one-screen answer. The live detail follows the table when something is serving
// or when the caller asked for it: an idle host has nothing to add, and a screen that repeats "none"
// four times is a screen an operator stops reading.
func Render(w io.Writer, s Snapshot, long bool) error {
	b := &bytes.Buffer{}
	fmt.Fprintf(b, "%s · %d profiles the deployment can serve\n", s.Host, len(s.Profiles))
	if s.Policy.Error != "" {
		fmt.Fprintf(b, "policy  %s — the table has no measured facts\n", policyProblem(s.Policy))
	}
	fmt.Fprintln(b)

	header := []string{"", "PROFILE", "PACK", "CTX × SLOTS", "ALIAS", "ROLE"}
	widths := make([]int, len(header))
	for i, cell := range header {
		widths[i] = utf8.RuneCountInString(cell)
	}
	for _, p := range s.Profiles {
		for i, cell := range row(p) {
			if n := utf8.RuneCountInString(cell); n > widths[i] {
				widths[i] = n
			}
		}
	}
	line := func(cells []string) {
		var out strings.Builder
		for i, cell := range cells {
			if i > 0 {
				out.WriteString("  ")
			}
			out.WriteString(cell)
			if i < len(cells)-1 {
				out.WriteString(strings.Repeat(" ", widths[i]-utf8.RuneCountInString(cell)))
			}
		}
		fmt.Fprintln(b, strings.TrimRight(out.String(), " "))
	}
	// One table, three groups: the columns must line up across all of them, so the widths come from
	// every row and the labels are printed between.
	for _, group := range []string{GroupFrontier, GroupCompanion, GroupImage} {
		rows := rowsOf(s, group)
		if len(rows) == 0 {
			continue
		}
		fmt.Fprintln(b, group)
		line(header)
		for _, p := range rows {
			line(row(p))
		}
		fmt.Fprintln(b)
	}

	if !long && !s.Loaded() {
		fmt.Fprintln(b, nowLine(s))
		_, err := w.Write(b.Bytes())
		return err
	}
	fmt.Fprintln(b, "now")
	live(b, s)
	_, err := w.Write(b.Bytes())
	return err
}

// row is one table line: the resting marker, the profile, what it loads, the window it serves, the
// names that reach it, and the one word that says what it is for.
func row(p Profile) []string {
	mark := " "
	if p.Resting {
		mark = "*"
	}
	return []string{mark, p.Name, orDash(p.Pack), window(p), orDash(strings.Join(p.Aliases, ", ")), p.Role}
}

// window is the profile's serving window: the tokens every slot is carved at, and how many slots
// share the card. `base` is a profile that keeps the base config's own number.
func window(p Profile) string {
	switch {
	case p.Context > 0:
		return fmt.Sprintf("%s × %d", tokens(p.Context), p.Slots)
	case p.Slots > 0:
		return fmt.Sprintf("base × %d", p.Slots)
	}
	return "—"
}

func rowsOf(s Snapshot, group string) []Profile {
	var out []Profile
	for _, p := range s.Profiles {
		if p.Group == group {
			out = append(out, p)
		}
	}
	return out
}

// nowLine is the trailing line of the short view: what is current, what sits beside it, and what is
// left on the card and in the host.
func nowLine(s Snapshot) string {
	free := fmt.Sprintf("%s VRAM free, %s RAM free", mib(s.Free.VRAMMiB), mib(s.Free.RAMMiB))
	if !s.Manager.Reachable {
		return fmt.Sprintf("now  the manager is unreachable at %s · %s", s.Manager.URL, free)
	}
	return fmt.Sprintf("now  profile %s · companions %s · %s",
		orNone(s.Manager.Profile), list(s.Manager.Companions), free)
}

// live is the long view: the loaded profile, the engine's own rate, every companion beside it, the
// leases in flight, the eviction epoch and the last switch.
func live(b *bytes.Buffer, s Snapshot) {
	if !s.Manager.Reachable {
		fmt.Fprintf(b, "  manager     unreachable at %s (%s)\n", s.Manager.URL, s.Manager.Error)
		fmt.Fprintf(b, "  free        %s\n", freeDetail(s))
		return
	}
	loaded := "none"
	if p := s.Row(s.Manager.Profile); p != nil {
		loaded = s.Manager.Profile + " · " + shape(p)
	} else if s.Manager.Profile != "" && s.Manager.Profile != "none" {
		loaded = s.Manager.Profile
	}
	fmt.Fprintf(b, "  profile     %s\n", loaded)
	if s.EngineRateTps != nil {
		fmt.Fprintf(b, "  rates       %.1f t/s (the engine's last completed request, %s)\n",
			*s.EngineRateTps, ago(s.EngineRateAt))
	}
	fmt.Fprintf(b, "  companions  %s\n", companions(s))
	fmt.Fprintf(b, "  leases      %d in flight, draining %s\n", s.Manager.InFlight, yesNo(s.Manager.Draining))
	fmt.Fprintf(b, "  eviction    %s\n", orDash(s.Manager.EvictionID))
	fmt.Fprintf(b, "  switch      %s\n", switchLine(s.Manager))
	fmt.Fprintf(b, "  llama-swap  %s\n", swapLine(s.Swap))
	fmt.Fprintf(b, "  free        %s\n", freeDetail(s))
}

// companions is each loaded companion with its footprint and, when the policy measured one, its
// decode rate beside a frontier.
func companions(s Snapshot) string {
	if len(s.Manager.Companions) == 0 {
		return "none"
	}
	var parts []string
	for _, name := range s.Manager.Companions {
		detail := name
		if p := s.Row(name); p != nil && p.Facts != nil {
			detail += " " + mib(p.Facts.VRAMTotalMiB())
			detail += beside(p.Facts, s.Manager.Profile)
		}
		parts = append(parts, detail)
	}
	return strings.Join(parts, "; ")
}

// beside is the companion's measured decode rate. The rate is always labelled with the profile it
// was measured beside: a number measured next to another profile is still useful, but quoting it as
// this profile's rate would be a lie.
func beside(f *Facts, profile string) string {
	measured := f.DecodeWithFrontier
	if len(measured) == 0 {
		return ""
	}
	if tps, ok := measured[profile]; ok {
		return fmt.Sprintf(", %.1f t/s beside %s", tps, profile)
	}
	names := make([]string, 0, len(measured))
	for name := range measured {
		names = append(names, name)
	}
	sort.Strings(names)
	return fmt.Sprintf(", %.1f t/s beside %s", measured[names[0]], names[0])
}

func switchLine(m Manager) string {
	if m.LastSwitch == nil {
		return "none recorded"
	}
	sw := m.LastSwitch
	out := fmt.Sprintf("%s → %s · %d s", orDash(sw.From), sw.To, sw.Seconds)
	if sw.From == "" {
		// The journal leaves `from` empty when the engine started from nothing; `— →` reads like a
		// missing fact rather than a cold start.
		out = fmt.Sprintf("started %s · %d s", sw.To, sw.Seconds)
	}
	if sw.Cause != "" {
		out += " (" + sw.Cause + ")"
	}
	if m.LastSwitchSecondsAgo != nil {
		out += fmt.Sprintf(" · %d s ago", *m.LastSwitchSecondsAgo)
	}
	return out
}

// ago is how long the engine's last rate line has been sitting in its log: a rate from before the
// last switch belongs to an engine that no longer exists, and the reader must be able to see that.
func ago(at *time.Time) string {
	if at == nil {
		return "unknown age"
	}
	d := time.Since(*at)
	switch {
	case d < 90*time.Second:
		return "just now"
	case d < 90*time.Minute:
		return fmt.Sprintf("%d min ago", int(d.Minutes()))
	default:
		return fmt.Sprintf("%d h ago", int(d.Hours()))
	}
}

func swapLine(s Swap) string {
	if s.Error != "" {
		return "unreachable at " + s.URL
	}
	return list(s.Running)
}

func freeDetail(s Snapshot) string {
	return fmt.Sprintf("VRAM %s of %s (%d%%) · RAM %s of %s (%d%%)",
		mib(s.Free.VRAMMiB), mib(s.Free.VRAMTotalMiB), percent(s.Free.VRAMMiB, s.Free.VRAMTotalMiB),
		mib(s.Free.RAMMiB), mib(s.Free.RAMTotalMiB), percent(s.Free.RAMMiB, s.Free.RAMTotalMiB))
}

// shape is what a profile costs: the pack, the window, and the two halves of the card it takes.
func shape(p *Profile) string {
	parts := []string{}
	if p.Pack != "" {
		parts = append(parts, p.Pack)
	}
	if w := window(*p); w != "—" {
		parts = append(parts, w)
	}
	if p.Facts != nil {
		parts = append(parts, fmt.Sprintf("%s weights + %s K/V", mib(p.Facts.VRAMMiB), mib(p.Facts.KVReserveMiB)))
	}
	if len(parts) == 0 {
		return "no facts"
	}
	return strings.Join(parts, " · ")
}

// JSON is the same snapshot as one object, so a script reads what the screen shows.
func JSON(s Snapshot) ([]byte, error) { return json.MarshalIndent(s, "", "  ") }

// tokens is a context window as an operator says it: 393216 is 384k, 1048576 is 1M.
func tokens(n int) string {
	const meg = 1 << 20
	if n >= meg && n%meg == 0 {
		return fmt.Sprintf("%dM", n/meg)
	}
	if n%1024 == 0 {
		return fmt.Sprintf("%dk", n/1024)
	}
	return fmt.Sprint(n)
}

// mib is a footprint in the unit a person reads: GiB above a gigabyte, MiB below.
func mib(v int) string {
	if v >= 1024 {
		return fmt.Sprintf("%.1f GiB", float64(v)/1024)
	}
	return fmt.Sprintf("%d MiB", v)
}

func percent(part, total int) int {
	if total <= 0 {
		return 0
	}
	return part * 100 / total
}

func policyProblem(p PolicyInfo) string {
	if p.Path == "" {
		return "none configured"
	}
	return p.Path + ": " + p.Error
}

func list(names []string) string {
	if len(names) == 0 {
		return "none"
	}
	return strings.Join(names, ", ")
}

func orDash(s string) string {
	if s == "" {
		return "—"
	}
	return s
}

func orNone(s string) string {
	if s == "" {
		return "none"
	}
	return s
}

func yesNo(v bool) string {
	if v {
		return "yes"
	}
	return "no"
}
