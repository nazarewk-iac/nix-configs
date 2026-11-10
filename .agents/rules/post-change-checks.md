---
type: Rule
description: "Run the checks a change needs by blast radius, with an ETA and a resource estimate per check. Prefer a direct agent or human check over a codified bundle; prove both harnesses load; build, activate and verify the affected hosts; keep the boot check supervised; honour a skip or defer instruction."
timestamp: 2026-11-10T05:55:00+01:00
---

# Post-change checks

Full doc: [docs/post-change-checks.md](../../docs/post-change-checks.md). Bundle catalog:
[checks/README.md](../../checks/README.md).

- **Pick the blast radius first.** docs → a parse check; `packages/**` → parse + the package build;
  shell or harness config → parse + `den-eval-*` + `devenv shell -- true` + a harness load check; host
  modules → parse + `den-eval-*` + a host toplevel build + activation; flake inputs → the full
  flake-update procedure.
- **A direct check beats a codified one.** The `checks/` bundles are tripwires for broad changes
  (shared plumbing, cross-cutting refactors, inputs). For a narrow change, run the command that
  exercises it: build the package, load the harness, build the host, call the service. Use a bundle
  only when you cannot name every affected path.
- **Estimate before you run.** The doc gives an ETA and a resource estimate per check. A host build
  costs minutes and tens of GB of disk; a `den-eval-*` check costs seconds. Say the estimate when you
  propose a long check.
- **Never run a bare `nix flake check`.** It takes about 11 minutes. Run a bundle, or one named
  standalone check.
- **Both harnesses must load.** `opencode plugin list` shows an id per plugin and the log has no
  `failed to load plugin`; `pi --version` and `pi --list-models` work. After an upgrade, a cached
  plugin failure clears only on `opencode api delete /api/debug/location --param location="$PWD"` or
  a service restart.
- **Build, then activate, then verify.** Build each affected host with `--option builders ""` unless
  the builder is known good. Activate in the order the owner names (default `moss`, `brys`, `etra`,
  `oams`, then `briv`, then `anji`), then check `systemctl is-system-running`, `systemctl --failed`,
  and the services the change touches.
- **The boot check is supervised by default.** Ask before a reboot unless the owner said the run is
  self-sufficient or asked for the reboot.
- **The owner can reduce the run.** A direct "build only", "skip the checks" or "defer checks"
  instruction wins; `KDN_AGENT_CHECKS=skip|defer|build-only` is the scriptable fallback. Record what
  was skipped, and never report an unrun check as passed.
