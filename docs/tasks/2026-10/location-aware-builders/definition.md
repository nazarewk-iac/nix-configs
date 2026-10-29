---
type: Task
description: Make remote builds location-aware without a rebuild — prefer `brys` at home, build locally when away, and make an unreachable builder degrade to local instead of failing the build.
status: open
authored_by: agent
timestamp: 2026-10-28T23:30:00+01:00
---

# Location-aware remote builders

## Context

`oams` is the laptop: it thermal-throttles, so it is the slowest way to build.
`brys` is a Ryzen 9 5950X (16c/32t) and roughly 3× the speed. Today
`modules/universal/profile/remote-builders/default.nix` lists every builder
statically and duplicates each one per network suffix:

```
ssh-ng://…@briv.lan.etra.net.int.kdn.im.  aarch64-linux  - 2 400 …
ssh-ng://…@briv.priv.nb.net.int.kdn.im.   aarch64-linux  - 2  80 …
```

Observed on `oams` today (`nix config show`):

```
builders                  = @/etc/nix/machines     # legacy text format
builders-use-substitutes  = false
max-jobs                  = 16
NIX_SSHOPTS               = <not set>
```

The desired behaviour: **at home, prefer `brys`; away, build locally unless
explicitly asked; never fail a build or a cache pull because a builder is
unreachable; switch automatically, without a rebuild.**

## The starting point is worse than expected

Checked on `oams` today, before designing anything:

```
$ sudo grep -c brys /etc/nix/machines
0
$ ssh kdn-nix-remote-build@brys.lan.etra.net.int.kdn.im true
Load key "/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519": Permission denied
Permission denied (publickey,keyboard-interactive).
```

Two findings:

1. **`brys` is not in `oams`'s builder list at all.** The pipeline in
   `remote-builders/default.nix:103` filters out every builder whose systems
   include `x86_64-linux` —
   `(builtins.filter (builder: !(builtins.elem "x86_64-linux" builder.systems)))`
   with the comment `# TODO: implement the most common "x86_64-linux" builder
   properly`. So the most common case in this fleet is deliberately skipped, and
   only the *foreign* systems (`aarch64-*`, darwin) actually dispatch. Every
   native build on `oams` is local today, whatever the config appears to say.
2. **The builder SSH identity is unreadable.** `ssh` runs as `kdn` and the key at
   `/run/configs/nix/ssh/kdn-nix-remote-build/id_ed25519` is root-only, so even a
   hand-added entry would fail at connect. The daemon runs the hook as root, so
   it can read the key — but any interactive test as `kdn` cannot, which is why
   phase 1 must be checked from a real `nix build`, not from `ssh` by hand.

So phase 1 is not "prove the switch works on top of an existing setup"; it is
"make `brys` a builder for `x86_64-linux` at all, then prove the switch".

## What the research settled

Full source-level notes: [research.md](research.md). The four findings that
shape the design:

1. **Native failover is connection-time only, not mid-build.** An unreachable
   builder is caught, disabled for that hook process, the next candidate is
   tried, and the build falls back to local. But once the hook has accepted the
   build, a remote that dies makes the goal **fail** — there is no local retry.
2. **There is no latency, location or load awareness.** Selection is
   `load / speedFactor` with static tie-breaks. `speedFactor` cannot encode
   "am I at home".
3. **The builder list is re-read per derivation**, so a plain file outside the
   store works as a runtime switch with **no daemon restart and no rebuild**.
   Lix 2.95 also accepts **TOML** builders with a per-machine `enable` flag,
   which is the cleanest switch.
4. **Lix sets no SSH `ConnectTimeout`.** A silently dropped link stalls the hook
   until the OS TCP timeout, so the failover in (1) never gets a chance quickly.

## Design

### The invariants

- **I1. Local is always available.** `max-jobs > 0` on every client. A remote is
  a speed hint, never a requirement. This alone satisfies "must not fail".
- **I2. The switch is a file write.** `nix.settings.builders = "@/run/kdn/nix-machines.toml"`
  (a plain, writer-owned path), `nix.buildMachines = [ ]`. A systemd timer
  rewrites it; the next build picks it up.
- **I3. A missing or malformed builder file must not break local builds.** Lix
  treats a missing **legacy** `@file` as empty, but a missing **TOML** file as a
  hard error — so the writer must always emit a valid TOML, even an empty one.
- **I4. The daemon always has an SSH timeout.** `NIX_SSHOPTS` with
  `ConnectTimeout`, `ServerAlive*` and `BatchMode=yes` in the daemon environment.
- **I5. One entry per physical host.** No per-suffix duplication; the writer
  decides *which URI* (LAN or NetBird) is enabled. Two entries for one host
  double-count its slots in selection.

### The two switches

| Mode | Detection | Enabled entries |
|---|---|---|
| **home** | `brys` reachable on its LAN name within ~2 s **and** the default route is the home gateway | `brys` on the LAN URI |
| **away** | otherwise | none (local only) |
| **away + explicit** | user asks | `brys` on the NetBird URI |

"Reachable" is a real probe (`ssh -o ConnectTimeout=2 -o BatchMode=yes …
true`), not a ping and not a DNS guess: the capability that matters is
"can a build hook open this connection".

### `brys` is special: it also serves models

A reachable `brys` is not always a *good* builder. When `llama-swap` holds the
frontier model, a build competes for the same RAM and CPU, and a 95 GiB model
resident means a big build can OOM it. The writer probes
`http://127.0.0.1:39700/running` through the builder entry and:
- keeps `brys` enabled when only small models are resident (cheap, GPU-bound);
- **disables** it when a frontier model is loaded, unless the user forces it.

This is the one place a DIY signal beats `speedFactor`, and it is the reason not
to hand the whole decision to Nix.

## Why not the alternatives

| Option | Verdict |
|---|---|
| `speedFactor` tuning | static; cannot express "at home". |
| `--builders` on the client | **dead in multi-user mode**: the daemon ignores it unless the client is trusted, and then only `""`. |
| Hydra / nix-eval-jobs / nix-fast-build | evaluation CI, not build dispatch for a laptop. |
| nixbuild.net | works as a normal remote builder, but commercial; out of scope. |
| harmonia / attic / nix-serve / cachix | **caches**, not dispatchers. Useful for the second half (do not rebuild what another host built), not the first. |
| A central scheduler on `etra` | legitimately useful, but only as a **generator** of the same TOML file; it adds a network dependency that the local writer must survive losing. |

## Phases

| Phase | Work | Gate |
|---|---|---|
| 1 | Prove the runtime switch: hand-write `/run/kdn/nix-machines.toml`, point `builders` at it, `nix build` something small. Confirm a change takes effect with no daemon restart. | a build lands on `brys` after a file edit |
| 2 | The writer: a systemd oneshot + timer owning the TOML, with home/away detection and the `brys` model-load probe. | the file flips on cable/Wi-Fi change within one timer interval |
| 3 | `NIX_SSHOPTS` on the daemon, `builders-use-substitutes = true`, and retire the per-suffix duplication. | an unreachable `brys` costs < 10 s and the build completes locally |
| 4 | Measure: same `nixos-rebuild` on `oams` local, on `brys` idle, and on `brys` with a model loaded. | numbers per case |
| 5 | Optional: a generator on `etra` and/or harmonia as a shared cache. | only if phases 1–4 leave a real gap |

## Measurement: the two questions that started this

1. **How much faster is `brys` than `oams`?** Wall-clock for the same
   `nixos-rebuild switch` of `oams`, built locally and on `brys`.
2. **Does building on `brys` hurt the LLMs, and by how much?** While a
   frontier model is resident, run a build and compare
   `tokens_per_second` and `duration_ms` from `/var/lib/llm-stats/` against
   an idle baseline, per alias. The collector from
   [../llm-metrics-persistence/](../llm-metrics-persistence/definition.md) is
   running and the desktop profile no longer reserves cores, so this is the
   right moment to answer it.

The answer decides the policy: if builds measurably degrade generation, the
model-load probe is mandatory and a build may need to preempt by
force-unloading the frontier, or wait.

## Acceptance

- With `brys` on the LAN, a build goes to it; with the cable out and no NetBird
  route, the same build completes **locally** without an error.
- Neither switch required a rebuild or a daemon restart.
- An unreachable `brys` costs a few seconds, not a TCP timeout.
- No build fails because a builder is down. A builder dying **mid-build** is
  documented as the one residual case (native Nix has no retry), with a decision
  on whether a retry wrapper is worth it.
- The measured tables from the two questions exist.

## Risks

| Risk | Mitigation |
|---|---|
| **A `brys` death mid-build fails the build** (native, unavoidable) | decide explicitly: accept, or add a retry wrapper. Not silently ignored. |
| Building on `brys` while a frontier model is resident OOMs it | the model-load probe disables it, unless forced |
| The TOML file is missing/malformed → every build errors | the writer always emits a valid file; a systemd `ExecStartPre` check |
| Home detection flaps on a slow link | hysteresis: enable immediately, disable only after N consecutive failures |
| `brys` is reachable but the SSH host key rotated | connection fails → connection-time failover to local (I1), and root's `known_hosts` is managed by the ssh-ca work |
| The NetBird URI is enabled but slow, making a build slower than local | `speedFactor` on the NetBird entry stays low, and it is enabled only when explicitly asked |
