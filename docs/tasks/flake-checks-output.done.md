---
type: Solution
description: Fixed the flake `checks =` wiring via `.config.output.mkSubmodule` and proved the plumbing with a minimal `hello` "hello world" check.
task: flake-checks-output.md
authored_by: agent
timestamp: 2026-07-31T11:12:00+02:00
---

# Solution — `flake.nix`'s `checks =` output

Task: [flake-checks-output.md](flake-checks-output.md).

## Root cause analysis

`self.kdnMetaModule` is the `lib.evalModules {...}` result — a module *configuration set*
(`{ _type = "configuration"; ... }`), **not** a function. Line 444 of `flake.nix` called it
directly (`self.kdnMetaModule { moduleType = "checks"; }`), so evaluation failed with
`attempt to call something which is not a function but a set`.

Every other call site in `flake.nix` (lines ~166, 181, 393, 459) instead goes through
`self.kdnMetaModule.config.output.mkSubmodule { moduleType = "..."; }`, which is the function
that returns the plain args attrset `callPackages` expects. Line 444 was the lone outlier.

Because `checks/default.nix` was an empty `{ }` stub until the `passthru.tests.pytest` work,
nothing had ever exercised this code path — so `.#checks` had likely **never** evaluated
successfully. Confirmed pre-existing at commit `21c72b92`, before that package work.

## Solution

1. **Fixed the wiring** in `flake.nix` (line ~444) to match the other call sites:
   ```nix
   checks = pkgs.callPackages ./checks (
     self.kdnMetaModule.config.output.mkSubmodule {
       moduleType = "checks";
     }
   );
   ```

2. **Added a minimal "hello world" check** to `checks/default.nix` to prove the
   `checks.<system>` plumbing evaluates *and* builds end-to-end, independent of the heavier
   pytest checks:
   ```nix
   hello = pkgs.runCommand "check-hello" { } ''
     echo "hello world"
     touch $out
   '';
   ```

## Verification steps

Run on this Darwin host (`aarch64-darwin`):

- `nix eval '.#checks.aarch64-darwin' --apply builtins.attrNames --json`
  → `["hello","kdn-slug-pytest","zellij-llm-pytest"]` (previously errored with the call-error).
- `nix build '.#checks.aarch64-darwin.hello' -L`
  → builds green, prints `hello world`.

## Follow-up notes

The two pytest checks (`kdn-slug-pytest`, `zellij-llm-pytest`) were **not** re-verified on a
genuinely sandboxed builder — this Darwin host runs `sandbox = false`. Only the `hello` check
is proven under real conditions. Re-verify the pytest suites on a sandboxed builder (e.g. Linux
CI with `sandbox = true`) before relying on `.#checks` for CI gating — `zellij-llm`'s test
spawns a real zellij server (unix-socket creation), which may behave differently under sandbox,
network, or `$HOME` restrictions.
