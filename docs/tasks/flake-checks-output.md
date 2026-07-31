---
type: Task
description: flake.nix's `checks =` output evaluated to a call-error because `self.kdnMetaModule` was invoked directly instead of via `.config.output.mkSubmodule`.
status: done
solution: flake-checks-output.done.md
authored_by: agent
timestamp: 2026-07-31T11:12:00+02:00
---

# `flake.nix`'s `checks =` output is broken — `self.kdnMetaModule` called directly instead of via `.config.output.mkSubmodule`

> ✅ **Done** — see the solution in [flake-checks-output.done.md](flake-checks-output.done.md).

**Status:** pre-existing bug, confirmed present at commit `21c72b92` (before any of the
`packages/llm/{kdn-slug,zellij-llm}` work that surfaced it) — not introduced by that work.
Discovered while trying to wire `kdn-slug`/`zellij-llm`'s new `passthru.tests.pytest` checks
(see `checks/default.nix`) into the flake's real `checks.<system>` output.

**Symptom:**
```
nix eval '.#checks.aarch64-darwin' --apply builtins.attrNames --json
# error: attempt to call something which is not a function but a set: { _type = "configuration"; ... }
#   at flake.nix:444:  checks = pkgs.callPackages ./checks (self.kdnMetaModule { moduleType = "checks"; })
```

**Root cause:** every other call site in `flake.nix` correctly goes through
`self.kdnMetaModule.config.output.mkSubmodule { moduleType = "..."; }` (see lines ~166, 181,
393, 459) to get a plain args attrset — `self.kdnMetaModule` itself is the `lib.evalModules
{...}` result (a module configuration set), not a function, so calling it directly at line
444 (`checks = pkgs.callPackages ./checks (self.kdnMetaModule { moduleType = "checks"; })`)
fails. This means **`.#checks` has likely never evaluated successfully** — `checks/default.nix`
was still an empty `{ }` stub when this was found, so nothing had exercised the code path.

**Fix (proposed at time of writing):** change line 444 to match the working pattern:
```nix
checks = pkgs.callPackages ./checks (
  self.kdnMetaModule.config.output.mkSubmodule { moduleType = "checks"; }
);
```
then verify `nix eval '.#checks.<system>' --apply builtins.attrNames --json` succeeds and
`nix build '.#checks.<system>.kdn-slug-pytest' '.#checks.<system>.zellij-llm-pytest'` actually
runs the pytest suites wired up in `packages/llm/{kdn-slug,zellij-llm}/default.nix`
(`passthru.tests.pytest`) and `checks/default.nix`.

**Also worth confirming when picked up:** the pytest checks were only verified to build/pass
on this Darwin host, which has `sandbox = false` in its Nix config (confirmed via `nix
show-config`) — meaning `nix-build`/`nix build` here provides no real sandbox isolation
either, so this is *not* proof the checks work under a genuinely sandboxed builder (e.g. Linux
CI with `sandbox = true`), where unix-socket creation (`zellij-llm`'s test spawns a real
zellij server) or network/`$HOME` restrictions could behave differently. Re-verify on a
sandboxed builder before relying on `.#checks` in CI gating.
