// Package walk enumerates every certificate declaration site of a flake.
//
// It reads the den tree and the legacy tree. A missing option is an empty set, never an error, so a
// target that adopts the tree partly is still walkable. A target whose subtree evaluation fails is
// not fatal either: the walk records the failure, keeps the readable targets, and lets the caller
// act on them. See design § 5.4.
package walk

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"

	"kdn-certs/internal/decl"
)

// Evaluator runs one `nix eval` and returns its JSON. The `apply` expression reshapes the value, so
// a missing option yields an empty set instead of an error.
type Evaluator interface {
	EvalJSON(attr string, apply string) ([]byte, error)
}

// NixEvaluator runs the real `nix eval --json` command against a flake.
type NixEvaluator struct {
	// Flake is the flake reference, for example `.`.
	Flake string
	// Verbose prints each command before it runs.
	Verbose bool
	// Logf receives one line per command when Verbose is set.
	Logf func(format string, args ...any)
}

// EvalJSON runs `nix eval --json <flake>#<attr> --apply <apply>`.
func (n NixEvaluator) EvalJSON(attr string, apply string) ([]byte, error) {
	args := []string{"eval", "--json", fmt.Sprintf("%s#%s", n.Flake, attr)}
	if apply != "" {
		args = append(args, "--apply", apply)
	}
	if n.Verbose && n.Logf != nil {
		n.Logf("nix %v", args)
	}
	out, err := exec.Command("nix", args...).Output()
	if err != nil {
		return nil, fmt.Errorf("nix eval %s: %w", attr, err)
	}
	return out, nil
}

// The apply expressions that make a missing option an empty set.
//
// `builtins` holds no `attrByPath` — that helper lives in `lib`, and `--apply` runs in a pure
// evaluation with no `lib` in scope. `builtins.foldl'` over the path does the same job: it walks
// the attribute set and returns the fallback at the first missing key.
const (
	applyCerts = `x: builtins.foldl' (v: k: if builtins.isAttrs v && v ? ${k} then v.${k} else { }) x [ "kdn" "certificates" "certs" ]`
	applyCAs   = `x: builtins.foldl' (v: k: if builtins.isAttrs v && v ? ${k} then v.${k} else { }) x [ "kdn" "ca-dag" "cas" ]`
	applyNames = `builtins.attrNames`
)

// Failure is one target whose subtree evaluation failed. The walk keeps the readable targets, so
// one broken host does not hide the rest.
type Failure struct {
	// Target is the target name, for example `nixosConfigurations.broken`.
	Target string `json:"target"`
	// Error is the failure message.
	Error string `json:"error"`
}

// Result holds the readable targets and the per-target failures of one walk.
type Result struct {
	// Targets are the targets whose declarations were readable.
	Targets []decl.Target
	// Failures are the targets whose subtree evaluation failed.
	Failures []Failure
}

// Err returns one aggregate error when a target failed, or nil when every target was readable.
func (r Result) Err() error {
	if len(r.Failures) == 0 {
		return nil
	}
	names := make([]string, 0, len(r.Failures))
	for _, failure := range r.Failures {
		names = append(names, failure.Target)
	}
	return fmt.Errorf("%d target(s) failed to evaluate: %s", len(r.Failures), strings.Join(names, ", "))
}

// Walk reads every declaration site of the flake and returns one Target per readable site.
//
// The den tree and the legacy tree are both read. A legacy host that no augmentation line reaches
// returns an empty set and raises no error. A target whose own subtree fails to evaluate is
// recorded under `Result.Failures`; the walk continues with the readable targets.
func Walk(e Evaluator) (Result, error) {
	var result Result

	// 1. den hosts. `den.hosts` is one host set per system.
	hostNames, err := names(e, "den.hosts", `x: builtins.concatLists (builtins.map builtins.attrNames (builtins.attrValues x))`)
	if err != nil {
		return Result{}, err
	}
	for _, host := range hostNames {
		readInto(&result, e, "denConfigurations."+host+".config", "denConfigurations."+host)
	}

	// 2. den home configurations.
	homeNames, err := names(e, "denHomeConfigurations", applyNames)
	if err != nil {
		return Result{}, err
	}
	for _, home := range homeNames {
		readInto(&result, e, "denHomeConfigurations."+home+".config", "denHomeConfigurations."+home)
	}

	// 3. den devenv shells. `den.devenv.mkShell` returns `.config` alone, so the read is one level
	// shorter than the host read.
	shellNames, err := names(e, "denDevenvShells", applyNames)
	if err != nil {
		return Result{}, err
	}
	for _, shell := range shellNames {
		readInto(&result, e, "denDevenvShells."+shell, "denDevenvShells."+shell)
	}

	// 4. The legacy tree. A universal host that sub-task 000 augments appears here.
	for _, output := range []string{"nixosConfigurations", "darwinConfigurations", "homeConfigurations"} {
		legacyNames, err := names(e, output, applyNames)
		if err != nil {
			return Result{}, err
		}
		for _, name := range legacyNames {
			readInto(&result, e, output+"."+name+".config", output+"."+name)
		}
	}

	return result, nil
}

// readInto reads one target. A readable target joins `result.Targets`; a failed one joins
// `result.Failures` and the walk continues.
func readInto(result *Result, e Evaluator, configAttr string, name string) {
	target, err := readTarget(e, configAttr, name)
	if err != nil {
		result.Failures = append(result.Failures, Failure{Target: name, Error: err.Error()})
		return
	}
	result.Targets = append(result.Targets, target)
}

// names reads one attribute-name list.
//
// A missing top-level flake output is an empty list, never an error. A flake that carries no
// `homeConfigurations` output is still walkable, exactly as a target that declares no certificate
// option is. The design's tolerance rule covers both.
func names(e Evaluator, attr string, apply string) ([]string, error) {
	raw, err := e.EvalJSON(attr, apply)
	if err != nil {
		return nil, nil
	}
	var list []string
	if err := json.Unmarshal(raw, &list); err != nil {
		return nil, fmt.Errorf("nix eval %s: %w", attr, err)
	}
	return list, nil
}

// readTarget reads the leaf set and the CA graph of one target.
func readTarget(e Evaluator, configAttr string, name string) (decl.Target, error) {
	target := decl.Target{Name: name, Certs: decl.Certs{}, CAs: decl.CAs{}}

	rawCerts, err := e.EvalJSON(configAttr, applyCerts)
	if err != nil {
		return target, err
	}
	if err := json.Unmarshal(rawCerts, &target.Certs); err != nil {
		return target, fmt.Errorf("nix eval %s certs: %w", configAttr, err)
	}

	rawCAs, err := e.EvalJSON(configAttr, applyCAs)
	if err != nil {
		return target, err
	}
	if err := json.Unmarshal(rawCAs, &target.CAs); err != nil {
		return target, fmt.Errorf("nix eval %s cas: %w", configAttr, err)
	}

	for certName, cert := range target.Certs {
		cert.Name = certName
		target.Certs[certName] = cert
	}
	for caName, ca := range target.CAs {
		ca.Name = caName
		target.CAs[caName] = ca
	}

	return target, nil
}

// MergeCAs merges every target's CA graph into one. A CA name that appears twice with different
// attributes is a hard error.
func MergeCAs(targets []decl.Target) (decl.CAs, error) {
	merged := decl.CAs{}
	for _, target := range targets {
		for name, ca := range target.CAs {
			existing, ok := merged[name]
			if !ok {
				merged[name] = ca
				continue
			}
			if !sameCA(existing, ca) {
				return nil, fmt.Errorf("CA %q appears in %q and %q with different attributes", name, existing.Name, target.Name)
			}
		}
	}
	return merged, nil
}

// sameCA compares two CA declarations by value, ignoring the target name.
func sameCA(a decl.CA, b decl.CA) bool {
	a.Name = ""
	b.Name = ""
	return fmt.Sprintf("%+v", a) == fmt.Sprintf("%+v", b)
}
