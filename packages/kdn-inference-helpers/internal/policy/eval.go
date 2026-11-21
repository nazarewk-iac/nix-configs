package policy

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// Plan is what the manager would do: what leaves, what stays, what arrives.
type Plan struct {
	Evict       []string `json:"evict,omitempty"`
	Keep        []string `json:"keep,omitempty"`
	Add         []string `json:"add,omitempty"`
	Profile     string   `json:"profile,omitempty"`
	WaitSeconds int      `json:"waitSeconds,omitempty"`
}

// Step is one node of the trace: which branch, which verb, what it saw.
type Step struct {
	Node   string         `json:"node"`
	Type   string         `json:"type"`
	Verb   string         `json:"verb,omitempty"`
	Result string         `json:"result"`
	Facts  map[string]any `json:"facts,omitempty"`
	Note   string         `json:"note,omitempty"`
}

// Refusal is the actionable part of a refusal, the same contract the companion gate already uses.
type Refusal struct {
	Code         int      `json:"code"`
	Reason       string   `json:"reason"`
	Alternatives []string `json:"alternatives,omitempty"`
	ConfirmField string   `json:"confirmField,omitempty"`
}

// Resulting is the predicted end state: what the admission is judged on.
type Resulting struct {
	Models  []string `json:"models"`
	VRAMMiB int      `json:"vramMiB"`
	RAMMiB  int      `json:"ramMiB"`
}

// Result is the decision plus its explanation.
type Result struct {
	Verdict   string    `json:"verdict"` // admit | refuse | wait
	Plan      Plan      `json:"plan"`
	Resulting Resulting `json:"resulting"`
	Why       []Step    `json:"why"`
	Explain   string    `json:"explain,omitempty"`
	Refusal   *Refusal  `json:"refusal,omitempty"`
}

const (
	verdictAdmit  = "admit"
	verdictRefuse = "refuse"
	verdictWait   = "wait"

	statusSuccess = "success"
	statusFailure = "failure"

	// maxTrace bounds the explanation so a pathological tree cannot flood a response.
	maxTrace = 200
)

type eval struct {
	p      *Policy
	req    Request
	active []Active
	st     State
	now    time.Time

	plan    Plan
	why     []Step
	verdict string
	refusal *Refusal
	explain string
	// victim is what `pick-victim` chose, so later checks can judge it.
	victim string
}

// Decide runs the tree over one request and returns the verdict with its trace.
func (p *Policy) Decide(req Request, active []Active, st State) Result {
	e := &eval{p: p, req: req, active: active, st: st}
	e.now = st.Now
	if e.now.IsZero() {
		e.now = time.Now()
	}
	if req.Class == "" {
		req.Class = "agent"
		e.req.Class = "agent"
	}
	if req.DeadlineSeconds == 0 {
		req.DeadlineSeconds = p.DefaultDeadline
		e.req.DeadlineSeconds = p.DefaultDeadline
	}

	e.run(p.Tree, "root")

	res := Result{Plan: e.plan, Why: e.why, Explain: e.explain, Refusal: e.refusal}
	switch {
	case e.verdict != "":
		res.Verdict = e.verdict
	case e.refusal != nil:
		res.Verdict = verdictRefuse
	default:
		res.Verdict = verdictRefuse
		res.Refusal = &Refusal{Code: 409, Reason: "no branch of the placement policy admitted this request"}
	}
	res.Resulting = e.resulting()
	return res
}

func (e *eval) run(n Node, path string) bool {
	// A decision is terminal: once an action has set the verdict, the remaining branches are moot.
	// Without this a refusal inside a branch would fall through to the next branch and be admitted.
	if e.verdict != "" {
		return true
	}
	switch n.Type {
	case "selector":
		for i, child := range n.Children {
			if e.run(child, fmt.Sprintf("%s.%d", path, i)) {
				e.step(path, "selector", "", statusSuccess, nil, fmt.Sprintf("branch %d admitted", i))
				return true
			}
		}
		e.step(path, "selector", "", statusFailure, nil, "every branch failed")
		return false
	case "sequence":
		for i, child := range n.Children {
			if !e.run(child, fmt.Sprintf("%s.%d", path, i)) {
				e.step(path, "sequence", "", statusFailure, nil, fmt.Sprintf("branch %d failed", i))
				return false
			}
		}
		e.step(path, "sequence", "", statusSuccess, nil, "")
		return true
	case "check":
		ok, facts, note := checks[n.Verb](e, e.args(n.Args))
		status := statusFailure
		if ok {
			status = statusSuccess
		}
		e.step(path, "check", n.Verb, status, facts, note)
		return ok
	case "action":
		ok, note := actions[n.Verb](e, e.args(n.Args))
		status := statusFailure
		if ok {
			status = statusSuccess
		}
		e.step(path, "action", n.Verb, status, nil, note)
		return ok
	}
	return false
}

func (e *eval) step(path, kind, verb, result string, facts map[string]any, note string) {
	if len(e.why) >= maxTrace {
		return
	}
	e.why = append(e.why, Step{Node: path, Type: kind, Verb: verb, Result: result, Facts: facts, Note: note})
}

// args resolves `$field` references against the blackboard.
func (e *eval) args(raw map[string]any) map[string]any {
	out := make(map[string]any, len(raw))
	for k, v := range raw {
		out[k] = e.resolve(v)
	}
	return out
}

func (e *eval) resolve(v any) any {
	s, ok := v.(string)
	if !ok || !strings.HasPrefix(s, "$") {
		return v
	}
	return e.lookup(strings.TrimPrefix(s, "$"))
}

// lookup walks `request.model`, `model.vramMiB`, `state.vramFreeMiB`, `policy.minDecodeTps`, `now`.
func (e *eval) lookup(path string) any {
	parts := strings.Split(path, ".")
	switch parts[0] {
	case "now":
		return float64(e.now.Unix())
	case "request":
		switch rest(parts) {
		case "model":
			return e.req.Model
		case "class":
			return e.req.Class
		case "deadlineSeconds":
			return float64(e.req.DeadlineSeconds)
		}
	case "model":
		m, ok := e.p.Models[e.req.Model]
		if !ok {
			return nil
		}
		switch rest(parts) {
		case "kind":
			return m.Kind
		case "tier":
			return m.Tier
		case "profile":
			return m.Profile
		case "vramMiB":
			return float64(m.VRAMMiB)
		case "ramMiB":
			return float64(m.RAMMiB)
		case "loadSeconds":
			return float64(m.LoadSeconds)
		case "switchSeconds":
			return float64(m.SwitchSeconds)
		case "persistent":
			return m.Persistent
		}
	case "state":
		switch rest(parts) {
		case "vramFreeMiB":
			return float64(e.st.VRAMFreeMiB)
		case "ramFreeMiB":
			return float64(e.st.RAMFreeMiB)
		case "draining":
			return e.st.Draining
		}
	case "policy":
		switch rest(parts) {
		case "minDecodeTps":
			return e.p.MinDecodeTps
		case "switchCooldownSeconds":
			return float64(e.p.SwitchCooldownSeconds)
		}
	}
	return nil
}

func rest(parts []string) string {
	if len(parts) < 2 {
		return ""
	}
	return strings.Join(parts[1:], ".")
}

func num(v any) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	}
	return 0, false
}

func str(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

// ---------------------------------------------------------------- checks

type checkFn func(e *eval, args map[string]any) (bool, map[string]any, string)

var checks = map[string]checkFn{
	"model-known":       checkModelKnown,
	"model-unknown":     checkModelUnknown,
	"model-disabled":    checkModelDisabled,
	"already-satisfied": checkAlreadySatisfied,
	"join-in-flight":    checkJoinInFlight,
	"cooldown-active":   checkCooldown,
	"profile-met":       checkProfileMet,
	"confirmed-profile": checkConfirmedProfile,
	"switch-affordable": checkSwitchAffordable,
	"tier-free":         checkTierFree,
	"fits-beside":       checkFitsBeside,
	"victim-available":  checkVictimAvailable,
	"victim-idle":       checkVictimIdle,
	"victim-settled":    checkVictimSettled,
	"victim-evictable":  checkVictimEvictable,
}

func checkModelKnown(e *eval, _ map[string]any) (bool, map[string]any, string) {
	_, ok := e.p.Models[e.req.Model]
	return ok, map[string]any{"model": e.req.Model}, ""
}

func checkModelUnknown(e *eval, _ map[string]any) (bool, map[string]any, string) {
	_, ok := e.p.Models[e.req.Model]
	return !ok, map[string]any{"model": e.req.Model}, ""
}

func checkModelDisabled(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok {
		return false, nil, ""
	}
	return m.Disabled, nil, ""
}

func checkAlreadySatisfied(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok {
		return false, nil, ""
	}
	if m.Kind == "engine" {
		for _, a := range e.active {
			if a.Kind != "engine" {
				continue
			}
			if m.Profile != "" && a.Profile == m.Profile {
				return true, map[string]any{"profile": a.Profile}, ""
			}
			if m.Profile == "" && contains(m.RequiresProfile, a.Profile) {
				return true, map[string]any{"profile": a.Profile}, "profile-neutral: the current profile satisfies it"
			}
		}
		return false, map[string]any{"profile": e.st.Profile}, ""
	}
	for _, a := range e.active {
		if a.Model == e.req.Model {
			return true, map[string]any{"loaded": true}, ""
		}
	}
	return false, nil, ""
}

func checkJoinInFlight(e *eval, _ map[string]any) (bool, map[string]any, string) {
	if e.st.Draining {
		return true, map[string]any{"draining": true}, "a switch is in progress; wait rather than start a second one"
	}
	for _, a := range e.active {
		if a.Model == e.req.Model && a.LoadingSince != nil {
			return true, map[string]any{"loadingForSeconds": e.now.Sub(*a.LoadingSince).Seconds()}, ""
		}
	}
	return false, nil, ""
}

func checkCooldown(e *eval, _ map[string]any) (bool, map[string]any, string) {
	if e.req.Class == "batch" {
		return false, map[string]any{"exempt": "batch"}, ""
	}
	if e.st.LastSwitchAt == nil {
		return false, nil, ""
	}
	age := e.now.Sub(*e.st.LastSwitchAt).Seconds()
	limit := float64(e.p.SwitchCooldownSeconds)
	if age < limit {
		return true, map[string]any{"secondsSinceSwitch": age, "cooldown": limit}, ""
	}
	return false, map[string]any{"secondsSinceSwitch": age}, ""
}

func checkProfileMet(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok {
		return false, nil, ""
	}
	if len(m.RequiresProfile) == 0 {
		return true, nil, ""
	}
	for _, allowed := range m.RequiresProfile {
		if allowed == e.st.Profile {
			return true, map[string]any{"profile": e.st.Profile}, ""
		}
	}
	return false, map[string]any{"profile": e.st.Profile, "requires": m.RequiresProfile}, ""
}

func checkConfirmedProfile(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok {
		return false, nil, ""
	}
	target := e.req.Confirm["kdn_switch_to"]
	if target == "" {
		return false, nil, ""
	}
	for _, allowed := range m.RequiresProfile {
		if allowed == target {
			return true, map[string]any{"target": target}, ""
		}
	}
	return false, map[string]any{"target": target, "allowed": m.RequiresProfile}, ""
}

func checkSwitchAffordable(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m := e.p.Models[e.req.Model]
	cost := m.SwitchSeconds
	if cost == 0 {
		cost = m.LoadSeconds
	}
	deadline := e.req.DeadlineSeconds
	ok := cost <= deadline
	return ok, map[string]any{"switchSeconds": cost, "deadlineSeconds": deadline}, ""
}

// checkTierFree enforces one model per tier: a tier is a promise about who may share the card.
func checkTierFree(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok || m.Kind == "engine" {
		return true, nil, ""
	}
	for _, a := range e.active {
		if a.Model != e.req.Model && a.Tier == m.Tier {
			return false, map[string]any{"tier": m.Tier, "resident": a.Model}, "the tier holds one model"
		}
	}
	return true, map[string]any{"tier": m.Tier}, ""
}

func checkFitsBeside(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m, ok := e.p.Models[e.req.Model]
	if !ok {
		return false, nil, ""
	}
	need := m.VRAMMiB
	free := e.st.VRAMFreeMiB
	ramNeed := m.RAMMiB
	ramFree := e.st.RAMFreeMiB
	if m.Kind == "engine" {
		// A profile switch stops the resident engine first, so "room beside it" is not the question.
		return true, map[string]any{"kind": "engine", "needMiB": need}, "a switch replaces the resident engine"
	}
	facts := map[string]any{"needMiB": need, "freeMiB": free, "ramNeedMiB": ramNeed, "ramFreeMiB": ramFree}
	if need > free || ramNeed > ramFree {
		return false, facts, "does not fit beside what is resident"
	}
	if m.DecodeWithFrontier != nil && e.p.MinDecodeTps > 0 {
		if observed, ok := m.DecodeWithFrontier[e.st.Profile]; ok {
			facts["decodeTpsBesideFrontier"] = observed
			if observed < e.p.MinDecodeTps {
				return false, facts, "would run below the service floor beside this profile"
			}
		} else {
			facts["decodeTpsBesideFrontier"] = "defaulted"
		}
	}
	return true, facts, ""
}

// checkVictimAvailable picks the model that would have to leave. Order is lexicographic on purpose:
// tier conflict first, then never used, then idle longest, then smallest. Weights can come later,
// when a case demands them.
func checkVictimAvailable(e *eval, _ map[string]any) (bool, map[string]any, string) {
	m := e.p.Models[e.req.Model]
	type candidate struct {
		a    Active
		idle float64
	}
	// If the request's own tier is occupied, only that occupant can resolve it: evicting anything
	// else would leave two models in the tier and break the invariant the eviction was meant to fix.
	tierOccupied := false
	for _, a := range e.active {
		if a.Model != e.req.Model && a.Tier == m.Tier {
			tierOccupied = true
		}
	}
	var candidates []candidate
	for _, a := range e.active {
		if tierOccupied && a.Tier != m.Tier {
			continue
		}
		if a.Model == e.req.Model {
			continue
		}
		if a.Kind == "engine" && m.Kind != "engine" {
			// The engine leaves only through a profile switch, never as a victim of a companion or
			// a small model: that would silently drop the frontier for a 2 GB model.
			continue
		}
		if a.LoadingSince != nil {
			continue // never evict something mid-load
		}
		if a.Leases > 0 {
			continue // never evict work in progress
		}
		if m.VRAMMiB > e.st.VRAMFreeMiB+a.VRAMMiB {
			continue // evicting it still would not make room
		}
		am, known := e.p.Models[a.Model]
		if known && am.Persistent {
			continue
		}
		idle := 1e9
		if a.LastFinishedAt != nil {
			idle = e.now.Sub(*a.LastFinishedAt).Seconds()
		}
		candidates = append(candidates, candidate{a: a, idle: idle})
	}
	if len(candidates) == 0 {
		return false, map[string]any{"candidates": 0}, "nothing can leave"
	}
	sort.Slice(candidates, func(i, j int) bool {
		ci, cj := candidates[i], candidates[j]
		// the model that occupies the request's own tier first: that is the structural conflict.
		// Evicting a companion to make room for a small model would leave two small models resident.
		iConflict := ci.a.Tier == m.Tier
		jConflict := cj.a.Tier == m.Tier
		if iConflict != jConflict {
			return iConflict
		}
		if ci.idle != cj.idle {
			return ci.idle > cj.idle
		}
		return ci.a.VRAMMiB < cj.a.VRAMMiB
	})
	chosen := candidates[0]
	e.victim = chosen.a.Model
	return true, map[string]any{"victim": chosen.a.Model, "idleSeconds": chosen.idle, "candidates": len(candidates)}, ""
}

func checkVictimIdle(e *eval, _ map[string]any) (bool, map[string]any, string) {
	for _, a := range e.active {
		if a.Model == e.victim {
			if a.Leases > 0 {
				return false, map[string]any{"victim": e.victim, "leases": a.Leases}, "in use"
			}
			return true, map[string]any{"victim": e.victim}, ""
		}
	}
	return false, map[string]any{"victim": e.victim}, "victim is not resident"
}

func checkVictimSettled(e *eval, _ map[string]any) (bool, map[string]any, string) {
	for _, a := range e.active {
		if a.Model != e.victim {
			continue
		}
		am, known := e.p.Models[a.Model]
		if !known || am.MinResidencySeconds == 0 || a.LoadedAt == nil {
			return true, map[string]any{"victim": e.victim}, ""
		}
		age := e.now.Sub(*a.LoadedAt).Seconds()
		if age < float64(am.MinResidencySeconds) {
			return false, map[string]any{"victim": e.victim, "residencySeconds": age, "required": am.MinResidencySeconds}, "the only victim finished loading recently"
		}
		return true, map[string]any{"victim": e.victim, "residencySeconds": age}, ""
	}
	return false, nil, ""
}

func checkVictimEvictable(e *eval, _ map[string]any) (bool, map[string]any, string) {
	am, known := e.p.Models[e.victim]
	if known && am.Persistent {
		return false, map[string]any{"victim": e.victim}, "persistent model"
	}
	return true, map[string]any{"victim": e.victim}, ""
}

// ---------------------------------------------------------------- actions

type actionFn func(e *eval, args map[string]any) (bool, string)

var actions = map[string]actionFn{
	"serve":          actionServe,
	"wait":           actionWait,
	"load":           actionLoad,
	"load-beside":    actionLoadBeside,
	"switch-profile": actionSwitchProfile,
	"evict":          actionEvict,
	"refuse":         actionRefuse,
}

func actionServe(e *eval, _ map[string]any) (bool, string) {
	e.verdict = verdictAdmit
	e.plan.Keep = e.activeIDs()
	m := e.p.Models[e.req.Model]
	// A profile-neutral engine (`qfn`) is served by whatever engine is resident; adding the request
	// name on top would count the same engine twice.
	served := false
	if m.Kind == "engine" {
		for _, a := range e.active {
			if a.Kind != "engine" {
				continue
			}
			if m.Profile == "" && contains(m.RequiresProfile, a.Profile) {
				served = true
			}
			if m.Profile != "" && a.Profile == m.Profile {
				served = true
			}
		}
	}
	if !served && !contains(e.plan.Keep, e.req.Model) {
		e.plan.Add = []string{e.req.Model}
	}
	e.explain = "served as-is: the model is already resident on a profile that satisfies it"
	return true, ""
}

func actionWait(e *eval, args map[string]any) (bool, string) {
	e.verdict = verdictWait
	seconds, _ := num(args["seconds"])
	if seconds <= 0 {
		seconds = 30
	}
	e.plan.WaitSeconds = int(seconds)
	e.plan.Keep = e.activeIDs()
	e.explain = "waiting: a load or a switch is already in progress for this model"
	return true, ""
}

func actionLoad(e *eval, _ map[string]any) (bool, string) {
	m := e.p.Models[e.req.Model]
	if m.Kind == "engine" {
		// Loading an engine profile means switching the engine. That evicts the resident engine and
		// every companion — a companion holds a reserve of the profile that is being replaced, which
		// is exactly what the manager's switch does before it starts the new engine. Small models
		// survive if the new engine leaves room.
		for _, a := range e.active {
			if a.Kind == "engine" || a.Kind == "companion" {
				e.plan.Evict = append(e.plan.Evict, a.Model)
			}
		}
		// A whole-card engine leaves nothing for the small models; keep only the ones that still fit.
		free := e.p.Budget.VRAMMiB - m.VRAMMiB
		for _, a := range e.active {
			if a.Kind != "small" {
				continue
			}
			if a.VRAMMiB <= free {
				free -= a.VRAMMiB
				continue
			}
			e.plan.Evict = append(e.plan.Evict, a.Model)
		}
		e.plan.Profile = m.Profile
		e.explain = fmt.Sprintf("switching the engine to profile %q", m.Profile)
	} else {
		e.explain = "loading beside what is resident"
	}
	e.plan.Keep = e.keepWithout(e.plan.Evict)
	e.plan.Add = []string{e.req.Model}
	e.verdict = verdictAdmit
	return true, ""
}

func actionLoadBeside(e *eval, _ map[string]any) (bool, string) {
	e.plan.Keep = e.activeIDs()
	e.plan.Add = []string{e.req.Model}
	e.verdict = verdictAdmit
	e.explain = "loaded beside the resident models: it fits the card and the speed floor"
	return true, ""
}

func actionSwitchProfile(e *eval, args map[string]any) (bool, string) {
	target := str(args["to"])
	if target == "" {
		target = e.req.Confirm["kdn_switch_to"]
	}
	e.plan.Profile = target
	// A switch unloads the engine and every companion: a companion's reserve belongs to the profile
	// that is being replaced. Keeping one would leave two companions or an over-full card.
	for _, a := range e.active {
		if a.Kind == "engine" || a.Kind == "companion" {
			e.plan.Evict = append(e.plan.Evict, a.Model)
		}
	}
	e.explain = fmt.Sprintf("switched the engine to %q as the caller confirmed", target)
	return true, ""
}

func actionEvict(e *eval, _ map[string]any) (bool, string) {
	if e.victim == "" {
		return false, "no victim chosen"
	}
	e.plan.Evict = append(e.plan.Evict, e.victim)
	e.explain = fmt.Sprintf("evicting %q to make room", e.victim)
	return true, ""
}

func actionRefuse(e *eval, args map[string]any) (bool, string) {
	code := 409
	if c, ok := num(args["code"]); ok {
		code = int(c)
	}
	reason := str(args["reason"])
	if reason == "" {
		reason = "the placement policy refused this request"
	}
	ref := &Refusal{Code: code, Reason: reason}
	if m, ok := e.p.Models[e.req.Model]; ok {
		switch {
		case len(m.RequiresProfile) > 0:
			ref.Alternatives = m.RequiresProfile
			ref.ConfirmField = "kdn_switch_to"
		case len(e.p.ColoProfiles) > 0 && m.Kind != "engine":
			// No profile requirement, but it needs room that only a reserve profile leaves.
			ref.Alternatives = e.p.ColoProfiles
			ref.ConfirmField = "kdn_switch_to"
		}
	}
	e.refusal = ref
	e.verdict = verdictRefuse
	return true, reason
}

// ---------------------------------------------------------------- helpers

func (e *eval) activeIDs() []string {
	out := make([]string, 0, len(e.active))
	for _, a := range e.active {
		out = append(out, a.Model)
	}
	sort.Strings(out)
	return out
}

func (e *eval) keepWithout(drop []string) []string {
	out := make([]string, 0, len(e.active))
	for _, id := range e.activeIDs() {
		if !contains(drop, id) {
			out = append(out, id)
		}
	}
	return out
}

func (e *eval) resulting() Resulting {
	keep := map[string]bool{}
	for _, id := range e.plan.Keep {
		keep[id] = true
	}
	for _, id := range e.plan.Evict {
		delete(keep, id)
	}
	for _, id := range e.plan.Add {
		keep[id] = true
	}
	var res Resulting
	for id := range keep {
		res.Models = append(res.Models, id)
	}
	sort.Strings(res.Models)
	for _, a := range e.active {
		if keep[a.Model] {
			res.VRAMMiB += a.VRAMMiB
			res.RAMMiB += a.RAMMiB
			delete(keep, a.Model)
		}
	}
	for id := range keep {
		if m, ok := e.p.Models[id]; ok {
			res.VRAMMiB += m.VRAMMiB
			res.RAMMiB += m.RAMMiB
		}
	}
	return res
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
}
