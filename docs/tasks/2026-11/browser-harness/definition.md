---
type: Task
description: Package browser-harness so Hermes Agent's browser_exec works, and run the browser on a host with CPU headroom instead of the router.
status: open
authored_by: agent
timestamp: 2026-11-21T15:00:00+01:00
---

# Browser harness for the Hermes gateway

## Context

Hermes Agent runs on `etra` as a nix-snapshotter container and answers through `qfn` via litellm.
Its `browser_exec` tool is **unavailable**: the core dependency `browser-harness` is not in nixpkgs,
and the tool's own `check_fn` hides it rather than failing loudly — the container log shows
`browser_exec_available returned False`. So "full browser control" is the one advertised capability
the gateway does not have.

Two separate problems, and only the first is packaging:

1. **The package is missing.** Hermes imports `browser_harness`; nixpkgs has nothing by that name.
   What it wraps (Playwright, raw CDP, pyppeteer, a bundled Chromium) has to be established from its
   `pyproject` before any decision — the packaging shape follows from that.
2. **The browser should not run on the router.** `etra` is the gateway: litellm, Caddy, containers.
   It has RAM to spare (31 GB) but four JasperLake cores, and a Chromium tab is the most CPU-hungry
   thing this fleet would run. A browser agent on the router is how the router becomes the
   bottleneck.

## Where the browser should run

| host                  | CPU                                   | verdict                                                                                 |
| --------------------- | ------------------------------------- | --------------------------------------------------------------------------------------- |
| `brys`                | 5950X, 16 cores, idle most of the day | **first choice** — headroom, and already the host that serves the heavy work            |
| `oams`                | laptop, 16 threads, 12 GB GPU         | second choice — it is an interactive machine, a browser steals from the person using it |
| `etra`                | 4 cores                               | **no** — the router stays a router                                                      |
| a future GPU-less box | unknown                               | a natural later home, once one exists                                                   |

The browser is a **service**, not a library call: a headless Chromium with a CDP endpoint, declared
as a container with a `stateDir` (profile, downloads, cache) so it is backed up and disposable like
everything else. Hermes then talks to it over the network instead of spawning it.

## Design sketch

- **Image**: Chromium (or the Playwright-bundled build) plus a small supervisor that starts it with
  `--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222`, a user-data dir under
  `KDN_STATE_DIR`, and `--no-sandbox` only if the container's seccomp makes the sandbox impossible
  (record which, and why).
- **Transport**: Hermes on `etra` reaches it over the tailnet. CDP has **no authentication** — the
  port must never be exposed beyond loopback or the tailnet, and a reverse proxy in front of it must
  require a token. This is the single most dangerous surface in the fleet: a CDP endpoint is
  arbitrary code execution in a browser profile.
- **CPU guard**: a cgroup limit (`CPUQuota`) on the browser container, so a runaway page cannot take
  the host, and so the "don't overload the router" rule becomes a number rather than an intention.
- **Fallback**: if packaging `browser-harness` is blocked, `browser_exec` stays hidden and the task
  records that as the accepted state rather than vendoring a wheel.

## Work items

1. **Establish what `browser-harness` is.** Read its `pyproject`/`setup.py` from the pinned Hermes
   source; list its dependencies and whether it bundles or downloads a browser. Acceptance: a
   written list, no guesses.
2. **Package it** in `packages/browser-harness/` with `buildPythonPackage` if the deps are in
   nixpkgs; if a dep is missing, report which and stop — do not vendor.
3. **Prove `browser_exec`** in the Hermes container against a local page (`data:` URL or a static
   file), then against a real site. Acceptance: the tool is visible in `hermes` and returns page
   text.
4. **Move the browser out of etra** if it works: a Chromium container on `brys` with a `stateDir`,
   `CPUQuota`, and a CDP endpoint reachable only from etra over the tailnet; Hermes configured to
   attach to it. Acceptance: `browser_exec` still works with Hermes on etra and Chromium on brys,
   and `etra`'s load average is unchanged during a page fetch.
5. **Document the security rule** in the task: CDP is unauthenticated, so it is loopback or tailnet
   only, with a token-checking proxy if it ever leaves the host.

## Risks

- **CDP is RCE.** Treat the endpoint as a shell. No public exposure, no shared profile with a
  logged-in session the fleet does not own.
- **Chromium in a container** needs care with the sandbox: `--no-sandbox` is a real loss, and the
  reason must be recorded if it is used.
- **State grows.** A browser profile is hundreds of MB and grows; the `stateDir` needs a quota, and
  the backup drill decides whether it is worth backing up at all (probably not — it is cache).
- **The tool hides itself.** A missing `browser_harness` makes `browser_exec` invisible rather than
  broken, which is why this went unnoticed; the Hermes startup log is the place to check.

## Order

1 → 2 → 3 first (packaging and the in-container proof), then 4 (moving it off the router) only if
the browser turns out to be worth keeping. If step 1 shows the harness downloads a browser at
runtime, the whole design changes: it becomes a container that must bake the browser in, and that
decision is recorded before any code is written.
