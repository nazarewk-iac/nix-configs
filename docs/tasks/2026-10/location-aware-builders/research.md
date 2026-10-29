---
type: Research
description: Source-verified behaviour of Lix and Nix remote builders — connection-time failover but not mid-build, no latency awareness, a per-derivation builder reload, TOML builders with enable flags, and the cache-versus-dispatch landscape.
task: definition.md
authored_by: agent
timestamp: 2026-10-28T23:25:00+01:00
---

# Dynamic remote builders for a home-lab (Lix): research notes

Retrieval date for every URL below: **2026-10-28** (git clones fetched the same day).
Environment verified locally: `nix (Lix, like Nix) 2.95.3` on `oams` (x86_64-linux).
The repository under discussion is `nazarewk-iac/nix-configs`; the file is
`modules/universal/profile/remote-builders/default.nix` (read only, not modified).

Sources of primary evidence, all cloned/read at the stated date:

- Lix: `https://git.lix.systems/lix-project/lix.git`, HEAD `67307889e3b3` (2026-10-29).
- Nix (CppNix): `https://github.com/NixOS/nix.git`, HEAD `f2f7406` (`2.36.0`).
- NixOS module patches vendored in this repo: `.flake.patches/nixpkgs/repo/nixos/modules/config/{nix-remote-build,lix-remote-build}.nix`.
- Nix docs (rendered): `https://nix.dev/manual/nix/latest/advanced-topics/distributed-builds.html` (2.35.4 manual).
- This repo's own prior finding: `docs/lix-caveats.md` (dated 2026-10-13).

Marking convention: **[VERIFIED]** = read in source or primary doc; **[UNVERIFIED]** = inferred or from secondary memory, not confirmed.

---

## Answer to question 6 first: graceful degradation

The requirement is "a build must never fail because a builder is unreachable."
The native mechanism does **not** fully deliver this. It delivers two weaker
guarantees, and the difference matters:

### 6a. Unreachable at *connection* time: handled, per build-hook process

**[VERIFIED — Lix `lix/legacy/build-remote.cc`]** `connectToBuilder()` loops over
candidate machines. If `openStore(bestMachine)` throws, it prints
`cannot build on '<machine>': <err>` and calls `bestMachine.disable()`, then
retries the next candidate:

```
} catch (std::exception & e) {
    printError("cannot build on '%s': %s", machineName, e.what());
    bestMachine.disable();
}
```

**[VERIFIED — Nix `src/nix/build-remote/build-remote.cc` ~line 262]** identical:
`printError("cannot build on '%s': %s%s", ...); bestMachine->enabled = false; continue;`.

Consequences:
- A stale **host key** or a **down SSH host** fails the *connection*; the hook
  disables that machine **for this hook process only** and tries the next
  machine. A fresh `build-remote` process is spawned per derivation
  (**[VERIFIED]** `derivation-goal.cc:1091-1095`, pool `instancesSem{4}`), and each
  process calls `getMachines()` again, so `disable()` does **not** persist across
  derivations. There is no cross-build health memory and no TTL. This is a
  per-derivation, per-process failover, not a health signal.
- If **no** machine connects and the build cannot be done locally, the hook
  replies `Decline`/`DeclinePermanently`/`Postpone`. **[VERIFIED]** In CppNix
  `derivation-building-goal.cc:504-546` `rpDecline` means "we should do it
  ourselves" and the goal falls through to `buildLocally()`. In Lix the same
  reply path lands in `tryLocalBuild()` (`derivation-goal.cc:724-758`). So an
  **unconnectable** set of builders degrades to local **iff** `max-jobs != 0` and
  the local machine can build the derivation (same system, required features
  available locally — `couldBuildLocally` in `build-remote.cc`).

### 6b. Fails *mid-build* after acceptance: the whole build FAILS, no local retry

**[VERIFIED — Lix `derivation-goal.cc:1034-1057` + `buildDone()` 955-985]**
After the hook accepts the job and the remote run raises, the goal resolves to
`BuildResult::MiscFailure` / `PermanentFailure` / `TransientFailure` and
`co_return done(...)`. `done()` (line 1408) sets
`exitCode = buildResult.success() ? ecSuccess : ecFailed`. Nothing re-enters
`tryToBuild`/`tryHookLoop` for that derivation.

**[VERIFIED — Nix `derivation-building-goal.cc:772-790]** the same:
`if (!statusOk(status)) { ... co_return std::move(e); }` with a failure result.
`build-remote.cc:386` throws `build of '<drv>' on '<storeUri>' failed: ...`.

**[VERIFIED — no retry wrapper]** `grep` for `retry|TransientFailure|tryAgain`
in `worker.cc` / `goal.cc` / `entry-points.cc` finds only the
`keepGoing`/`ecFailed` kill loop, never a re-submission of the same goal.

**So the honest statement is:** remote-build failure during the build is *not*
transparently retried locally. `TransientFailure` exists as a status but is not
acted upon for distributed builds. The only local fallback is when the remote
is unreachable *before* the hook accepts.

### 6c. The known-good pattern that satisfies "never fail"

Because of 6b, the pattern is **not** "list brys and hope Nix falls back." It is:

1. **Keep a local builder always present.** Local building is not an entry in
   `builders`; it is the daemon itself, controlled by `max-jobs`. Set
   `max-jobs > 0` (default 1; this repo uses 6 on `oams`). A local build
   cannot fail due to network. **[VERIFIED — `max-jobs.md`]**: "`0` is useful
   when using remote builders to prevent any local builds." Leaving it non-zero
   keeps the local escape hatch.
2. **Treat remote builders as a speed optimisation, not a correctness
   dependency.** `preferLocalBuild = true` derivations are never sent remotely
   **[VERIFIED — `derivation-build goa:716-720`, `willBuildLocally`]**, and
   `--builders ''` on the CLI disables remotes for one invocation
   **[VERIFIED — Nix `build-remote.cc:382` hint text]**.
3. **Use `builders-use-substitutes = true`** **[VERIFIED — `builders-use-substitutes.md`]**
   so a remote builder pulls deps from its own caches instead of waiting for
   the laptop to upload them. It does not change failure semantics; it only cuts
   the upload window (and thus the window in which a flaky link can fail the
   build).
4. **Accept the 6b residual risk, or eliminate it with a wrapper.** If a build
   *must* survive "brys dies at minute 40", the only native-free answer is to not
   route it remotely (or to re-run). A wrapper around `nix build` that retries on
   the specific "failed on remote builder" error is DIY and not provided by Nix/Lix.
5. **[UNVERIFIED, but strongly implied]** A *connection*-time disable doing the
   work means the practical failure mode is "extra ~SSH connect delay, then
   local", not "build fails", **provided** the host is unreachable in a way SSH
   reports quickly. There is **no `ConnectTimeout` set by Lix** **[VERIFIED —
   `lix/libstore/ssh.cc:addCommonSSHOpts`]**: only `$NIX_SSHOPTS`, `-i`, `-p`,
   host-key file and `-C` are passed. A silent host (packets dropped) therefore
   stalls until the OS TCP timeout (~2 min+) before the hook moves on. Setting
   `NIX_SSHOPTS="-o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2"`
   in the daemon environment is the fix, and it is DIY config, not a Nix feature.

**Bottom line for Q6:** native Nix/Lix gives *connection-time* failover to the
next builder and to local; it does **not** give *mid-build* failover. The
"never fail" requirement is satisfied only by keeping local building enabled and
treating remotes as optional, plus an SSH connect timeout of your own.

---

## Question 1: what Nix/nix-daemon offers natively (2026)

### Config surface

- `builders` (a.k.a. `NIX_REMOTE_SYSTEMS`) — semicolon/newline separated list
  or `@file` indirection. Default `@/etc/nix/machines`.
  **[VERIFIED — `lix/libstore/settings/builders.md`]**.
- `builders-use-substitutes` (bool, default `false`). Remote hosts fetch their
  own deps instead of receiving uploads. **[VERIFIED — settings md]**.
- `max-jobs` — local build parallelism; `0` disables all local builds except
  `preferLocalBuild`. **[VERIFIED — `max-jobs.md`]**.

### Per-machine fields

**[VERIFIED — `lix/libstore/machines.cc` legacy parser, lines 83-160; and the
TOML parser `lix/lix-rs/src/machines.rs`]** Column order in the legacy
space-separated file:

| # | Field | Default | Notes |
|---|---|---|---|
| 1 | store URI | required | `ssh-ng://user@host`, schemeless gains `ssh://` |
| 2 | system-types | local system | comma-separated |
| 3 | ssh key file | `""` | `-` means unset |
| 4 | `maxJobs` | `1` | positive int |
| 5 | `speedFactor` | `1.0` | float; `0` is coerced to `1`; `<0` errors |
| 6 | supported-features | `{}` | comma-separated |
| 7 | mandatory-features | `{}` | comma-separated |
| 8 | ssh-public-host-key | `""` | **base64**; sets `-oUserKnownHostsFile` to a temp file |

- `publicHostKey` **[VERIFIED — `ssh.cc:addCommonSSHOpts`]**: if set, Lix writes
  `host <decoded key>` to a temp file and passes `-oUserKnownHostsFile=`. This
  **bypasses root's `~/.ssh/known_hosts`** for that builder. If a host's key
  rotates and your baked-in base64 is stale, the connection fails exactly like
  an unknown host, and 6a's disable-and-move-on applies. If the field is `-`,
  root's `known_hosts` decides. **[VERIFIED — docs warning in
  `distributed-builds.md`]**.
- `protocol` in the NixOS module (`ssh` vs `ssh-ng`); ssh-ng is the modern
  one and is what this repo already uses (`defaults.protocol = "ssh-ng"`).

### Selection algorithm

**[VERIFIED — `selectBestMachine()` in `build-remote.cc:92-143`]**:
1. `is_eligible(system, requiredFeatures)` — enabled **and** system supported
   **and** required-features ⊆ (supported ∪ mandatory) **and** mandatory ⊆ required.
2. Open up to `maxJobs` slot lock files under
   `<stateDir>/current-load/<uri>-<n>`; count held locks as `load`.
3. Score by **lowest `load / speedFactor`**; tie-break: higher `speedFactor`,
   then lower `load`.
4. If none free but ≥1 eligible → `BuildRejected::Temporarily` (hook Postpone →
   parent waits and retries the *hook*, not a local build); if none eligible and
   local is impossible → `Permanently`; else `Permanently` (→ local attempt).

No ping, no latency, no distance, no history. Speed factor is a static float
you write by hand. **[VERIFIED — no `latency|ping|rtt|probe|reachab` hits in
`machines.cc`, `machines.rs`, `build-remote.cc`]**.

### Stale host key / down host — what actually happens

Covered in Q6a. Summary: connection error → that machine disabled for the
process → next machine → if none, local attempt (if possible). **No retry of a
build that got past connection.**

---

## Question 2: native latency/location awareness

**None exists. [VERIFIED]** No code path in either Lix or Nix measures or uses
latency, RTT, ping, or network location for builder selection. `speedFactor` is
the only cost signal and it is static. The `nc`/`ssh-ping` TODO in this repo's
own file is a legitimate DIY idea precisely because the daemon has no such
feature. Nothing in the 2.92-2.95 Lix release notes introduces one
(`doc/manual/src/release-notes/rl-2.9x.md` read; only TOML config is new).

---

## Question 3: can `nix.buildMachines` change without a rebuild?

**No, not through the declarative path; yes, in principle, through the file
the daemon re-reads — with caveats.**

- **[VERIFIED — Nix manual, `distributed-builds.html`]**: "After making changes
  to `nix.conf`, restart the Nix daemon for changes to take effect." There is no
  config reload signal. **[VERIFIED]** `grep` for `reload|SIGHUP|RELOAD` in
  `lix/nix/daemon.cc`, `nix/src/nix/unix/daemon.cc`, `globals.cc` finds only
  signal-handler installation, no re-parse of `nix.conf`.
- **BUT the `builders` setting is re-evaluated per build-hook process.** Each
  derivation spawns a new `build-remote`, which calls `getMachines()` →
  re-reads the `@file` from disk **[VERIFIED — `build-remote.cc:361`,
  `machines.cc:179-190`, `machines.rs:get_toml_machines` reads the file every
  call]**. So if `builders` points at a **regular file you own** (not a
  `/nix/store` symlink), editing that file changes builder selection for the
  **next build** without restarting the daemon.
- **The catch:** on NixOS, `nix.buildMachines` generates `/etc/nix/machines` as
  an `environment.etc` entry **[VERIFIED — vendored `nix-remote-build.nix`:
  `environment.etc."nix/machines" = ... text = buildMachinesText;`]**, and that is
  an activation-managed file (and on many systems a store symlink). Hand-editing
  it survives until the next activation. Two clean options:
  1. Point `builders = "@/run/nix-machines"` (or `/etc/nix/machines.d/*`) at a
     path a **systemd unit/timer writes**; leave `nix.buildMachines` empty. Then
     a timer can rewrite it any time, no rebuild, no daemon restart.
  2. Use the Lix **TOML** format with per-machine `enable = true|false`
     **[VERIFIED — `machines.rs` `FileMachine.enabled`, filtered in
     `into_machines`]** and have the writer flip `enable` bits.
- **[VERIFIED — daemon override rules]** In multi-user mode the daemon
  **rejects client-supplied `builders` except the empty string** ("Ignoring the
  client-specified setting 'builders' ... restricted setting") — `daemon.cc:244-254`.
  So a client `nix build --builders '...'` is **silently ignored** when talking to
  the daemon in multi-user mode. **This kills the "wrapper passes --builders"
  idea** unless the wrapper runs as a trusted user or as root. This is a
  critical, easily-missed detail and directly affects the recommended design.
- **`nix.settings` vs hand-written file:** `nix.settings.builders` on NixOS
  lands in `/etc/nix/nix.conf` and is store/activation managed; same restart
  story. A file outside `/nix/store` that the `builders = "@..."` setting points
  to is the runtime-switchable seam.

**Feasibility verdict:** a runtime-switchable builder list **is** feasible
without rebuild — writer service + a plain file + `builders = "@that/file"` —
because the hook re-reads it per build. It is **not** feasible through
`--builders` from an unprivileged client against the daemon.

### Lix 2.95 TOML builders (new, relevant)

**[VERIFIED — release notes `rl-2.95.md` cl/4533; `machines.rs`]** Lix ≥ 2.95
accepts a TOML file:

```toml
version = 1
[machines.brys]
uri = "ssh-ng://builder@brys.lan.etra.net.int.kdn.im."
system-types = ["x86_64-linux"]
jobs = 12
speed-factor = 32
enable = true
```

- `enable = false` drops the machine at parse time — the native "statically
  disable" switch **[VERIFIED]**.
- Format detection: tries TOML; on *syntactic* failure retries legacy; a missing
  `.toml` file is a **hard error** ("No such file"), whereas a missing legacy
  `@file` yields an **empty list** (silently zero builders)
  **[VERIFIED — `machines.rs:210-236` and test `bad_toml_file_doesnt_retry_legacy`]**.
  This asymmetry matters: a typo'd TOML path breaks every build; a typo'd legacy
  path silently disables remote building (which 6a turns into "builds locally").
- The repo already vendors a `lix.buildMachines` NixOS module
  (`.flake.patches/.../lix-remote-build.nix`) that emits TOML and sets
  `nix.settings.builders = "@<generated machines.toml>"`, and it asserts
  `config.nix.package.pname == "lix"` and `version >= 2.95`. So the TOML route
  is already wired in this tree — but the generated file is still a store path,
  so the "edit at runtime" trick needs a non-store output.

---

## Question 4: external schedulers / proxies / caches

Distinguish **dispatch** (chooses where to build) from **cache** (stores
outputs). Very few products dispatch; most cache. Statuses checked 2026-10-28.

| Project | What it does | Dispatch? | Cache? | Degrades when target down? | Status / link |
|---|---|---|---|---|---|
| **nixbuild.net** | Commercial build cluster; behaves as one remote builder URI; auto-scales 1-16 vCPU; auto-retries OOM builds | Yes (cloud) | Yes (result reuse) | Yes — it's the target, not a dependency; unreachable = your local builder | Active, €0.12/CPU-hr, 25 free CPU-hr/mo. `https://nixbuild.net`, `https://docs.nixbuild.net/terms` |
| **Hydra** | CI: evaluates jobs, dispatches to its own build machines | Yes (CI-scale) | Via `nix-serve`/harmonia | Queue-based; a dead builder = job stays queued | Maintenance mode; not for a laptop. `github.com/NixOS/hydra` |
| **nix-eval-jobs** | Parallel evaluation → JSON; no building | No | No | n/a | Active; latest commits 2026-09-17. `github.com/NixOS/nix-eval-jobs` |
| **nix-fast-build** | Wraps `nix-eval-jobs` + `nix-output-monitor`; invokes `nix build` | Yes (thin) | No | Fails if the `nix build` it launches fails | Active; push 2026-10-25, 565★, MIT. `github.com/Mic92/nix-fast-build` |
| **harmonia** | Rust binary cache + optional `harmonia-daemon` remote-build bridge | Optional (daemon bridge) | Yes | Cache misses just build locally | **Active, v3.3.0 (2026-09-18)**, includes `harmonia-gc`. `github.com/nix-community/harmonia` |
| **attic** | Multi-tenant Rust binary cache | No | Yes (chunked, dedup) | Cache: substitute failure falls through to build | Active; pushed 2026-10-26, 2134★. `github.com/zhaofengli/attic` |
| **nix-serve** | Perl narinfo/NAR server over a store | No | Yes (serves local store) | Substitute fallback | Alive but slow-moving; pushed 2025-11-24. `github.com/edolstra/nix-serve` |
| **nar-serve** | Node NAR proxy (cache routing) | No | Proxy | Falls through | Small project; **[UNVERIFIED current]** |
| **cache.nixos.org** | Central official cache | No | Yes | Substitute miss → build | Active |
| **cachix** | Hosted binary cache (Cachix) | No | Yes | Substitute miss → build | Active commercial |
| **devenv cache** | devenv's cache | No | Yes | Substitute miss → build | Active |
| **garnix** | Hosted CI + cache | Yes (CI) | Yes | CI reruns; not interactive | Active commercial. `garnix.io` |
| **nix-ci** | Hosted CI | Yes (CI) | Yes | CI reruns | **[UNVERIFIED current]** |
| **nix-remote-build-controller** | K8s controller scale-to-N remote builders | Yes (K8s) | No | Controller-level | 2★, Go, 2025-09. `github.com/omarjatoi/nix-remote-build-controller` |

**Dispatch-balancing projects that maintain a dynamic builder list: essentially
none for a home-lab.** A GitHub search for "nix builder dynamic" returns the K8s
controller above (2 stars) and nothing else relevant. **[VERIFIED by search;
absence is hard to prove, so treat as "no established project found"]**.

Key architectural point: **no cache makes a build "never fail" either** — a cache
is a substituter, and a substituter being down already falls through to build
that is *not* the same as the builder being down mid-build.

---

## Question 5: remote-builder health-check prior art

All of the following are **DIY patterns**; none is a shipped Nix feature.
Novelty is low and I could not find a canonical, widely-cited implementation.
Treat each as **[UNVERIFIED as a working recipe]**, offered as design shapes:

- **systemd timer rewrites `/etc/nix/machines`**: a `Type=oneshot` timer runs
  `ssh -o ConnectTimeout=2 -o BatchMode=yes brys true` (or `ssh-ping`, which
  this repo's TODO already cites: `ssh-ping -W2.5 -c10 -i 0 -n briv22`) and
  writes/clears the file or flips `enable` in a TOML. Feasible **[VERIFIED]**
  because the hook re-reads the file per build (Q3).
- **flake output generating machines**: produce the TOML from
  `nixosConfigurations` and consume it — but it lands in the store, so a rebuild
  is still needed to change it; the timer-writes-a-plain-file variant is what
  actually avoids the rebuild.
- **`distributedBuilds` toggled by a wrapper**: **does not work from an
  unprivileged client** against the daemon **[VERIFIED — daemon.cc override
  rules]**. It works only if the wrapper runs as root/trusted, or you use a
  single-user install, or you run `nix --store local` bypassing the daemon.
- **NetworkManager dispatcher / systemd-networkd hooks** that detect "on home
  SSID / on the LAN subnet / WireGuard up" and rewrite the file: this is the
  location-awareness hook that Nix lacks. DIY, reliable, no Nix change.

I searched for blog posts/forum threads and did not retrieve a specific canonical
one worth citing as primary; the patterns above come from the source behaviour,
not from a third-party write-up. **[UNVERIFIED citations intentionally omitted.]**

---

## Question 7: recommended architecture for this exact setup

Constraints recap: `oams` throttles; `brys` fast but contended by llama-swap;
away-from-home must build locally unless asked; switching must be automatic;
builds/cache pulls must never fail for a dead builder; they are open to a
central dispatcher plus a purely local fallback.

### Recommended shape (in order of value for effort)

1. **Keep `max-jobs > 0` locally — this is the "never fail" foundation.**
   Already the case. Never run `max-jobs = 0` on `oams`. Remote builders are a
   speed hint, not a requirement. **[VERIFIED — Q6]**

2. **Runtime-switchable builder file, not `nix.buildMachines`.**
   - Set `nix.settings.builders = "@/run/kdn/nix-machines.toml"` (a *plain* file
     outside `/nix/store`) and leave `nix.buildMachines = [ ]`.
   - A small writer (systemd `oneshot` + timer) owns that file.
   - Because each `build-remote` re-reads it per derivation, edits take effect
     on the next build **without a daemon restart** **[VERIFIED — Q3]**.
   - Use the **Lix TOML** format with `enable` so the writer flips one boolean
     per host rather than rewriting a whole list.

3. **Location detection = the writer's input, not Nix's.**
   - "At home" = reachable `brys` on LAN (`ssh -o ConnectTimeout=2 -o
     BatchMode=yes brys.lan… true` succeeds within e.g. 2 s) **and** a cheap
     LAN probe (default-route gateway MAC / SSID / `systemd-networkd` state).
   - At home → enable `brys.lan…` (speed-factor 32), disable the WireGuard
     duplicate. Away → disable `brys` entirely (`enable = false`), keep local.
   - Do **not** rely on `speedFactor` to encode location; it is static. Encode
     location by which entries are `enable`d. **[VERIFIED — no native latency]**

4. **Always give the daemon an SSH connect timeout.** Set, in the
   `nix-daemon` environment, `NIX_SSHOPTS="-o ConnectTimeout=5 -o
   ServerAliveInterval=5 -o ServerAliveCountMax=2 -o BatchMode=yes"`. Without
   this, a silently-dropped LAN link stalls the hook for the TCP timeout before
   6a can move on. **[VERIFIED — Lix sets no ConnectTimeout]**

5. **`builders-use-substitutes = true`** so `brys` pulls deps from
   cache.nixos.org instead of receiving a slow upload over WireGuard.
   **[VERIFIED — settings md]**

6. **Retire the per-suffix duplication.** Instead of listing each host twice
   (LAN factor 100, WG factor 20), list `brys` once and let the *writer* decide
   which URI (LAN vs WG) is enabled for "home" vs "roaming". Cleaner and it
   removes the "same machine counted twice in selection" problem, since
   selection scores `load/speedFactor` and two entries for one physical host
   double-count its slots.

7. **Central scheduler = optional, later.**
   - The cheapest "central" option that fits a home-lab is **not** Hydra; it is
     **a builder-file generator on `etra`** that every client's daemon polls
     (e.g. `curl` from a timer into `/run/kdn/nix-machines.toml`). `etra` already
     exists and is always on.
   - If they later want real dispatch and cross-machine result sharing, add
     **harmonia** (`v3.3.0`) as a binary cache on `etra`/`brys`; that solves
     "don't rebuild what another host built" far more than it solves dispatch.
   - **nixbuild.net** is out of scope per the prompt; note it behaves as a normal
     remote builder so it drops into the same file if ever wanted.

8. **Purely local fallback** is already items 1+2: if the writer produces an
   empty/`enable=false`-only file, remote building is off and everything builds
   locally. A missing legacy `@file` is silently empty **[VERIFIED]**, but a
   missing `.toml` is a hard error **[VERIFIED]**, so the writer must always
   write a valid TOML file (even when empty) rather than delete it.

### DIY vs off-the-shelf

| Part | Off-the-shelf | DIY |
|---|---|---|
| "Never fail" core (local always available) | **Yes** — `max-jobs > 0` | — |
| Runtime-switchable list | partially (Lix TOML `enable`) | writer service |
| Location detection | no | **yes** (probe + network state) |
| SSH connect timeout | no | **yes** (`NIX_SSHOPTS`) |
| Mid-build failover | **no** (Q6b) | retry wrapper (optional) |
| Result sharing across hosts | **yes** (harmonia/attic) | wiring |
| Central dispatch | none suitable | `etra`-hosted file generator |

### Failure modes to design for

- **`brys` up but generating** (llama-swap): reachable, so selection sends the
  build; the build competes for CPU and is slow. Native Nix cannot see llama-swap
  load. Mitigation: the writer can *disable* `brys` while a model is loaded
  (probe llama-swap's HTTP status), or lower its `jobs`. This is DIY and is the
  main reason not to hand the whole decision to `speedFactor`.
- **`brys` dies mid-build**: the build **fails** (Q6b). Nothing native fixes
  this. If unacceptable, a `nix build` retry-on-"failed on remote builder"
  wrapper is required.
- **Stale `publicHostKey`**: connection fails, disable-and-local (Q6a). Prefer
  omitting `publicHostKey` and managing root's `known_hosts` if keys rotate, or
  keep the field correct.
- **Typo'd TOML path**: every build errors ("No such file"). Have the writer
  guarantee the file exists.
- **Two entries per physical host** (current config): doubles the host's
  apparent slots in selection; keep one entry and toggle its URI.

---

## Appendix: exact source anchors

- Lix `lix/legacy/build-remote.cc`: `selectBestMachine` 92-143;
  `connectToBuilder` 220-300 (disable-and-next at ~285); `runImpl` 431-553
  (trusted → `buildDerivation`, else `buildPathsWithResults`).
- Lix `lix/libstore/build/derivation-goal.cc`: hook call 724-758; buildDone
  955-985; `done()` 1408-1450; per-build hook spawn 1082-1116.
- Lix `lix/libstore/machines.cc`: legacy parser 83-177; `@file` expansion 60-90;
  `getMachines()` 179-190.
- Lix `lix/lix-rs/src/machines.rs`: TOML parse, `enable` filter, format
  detection 196-236; `is_eligible`/`disable` 130-160.
- Lix `lix/libstore/daemon.cc`: client-setting filter 195-260 (`builders` only
  `""` unless trusted).
- Lix `lix/libstore/ssh.cc`: `addCommonSSHOpts` (no ConnectTimeout).
- Lix docs: `doc/manual/src/advanced-topics/distributed-builds.md`,
  `lix/libstore/settings/{builders,builders-use-substitutes,max-jobs,build-hook}.md`,
  `doc/manual/src/release-notes/rl-2.95.md` (TOML builders, cl/4533).
- Nix `src/nix/build-remote/build-remote.cc`: `enabled=false; continue;` ~262;
  failure throw ~386.
- Nix `src/libstore/build/derivation-building-goal.cc`: `rpDecline`→local
  504-546; remote-first loop 580-600; mid-build failure 772-790.
- NixOS modules (vendored): `nix-remote-build.nix` (legacy text →
  `/etc/nix/machines`), `lix-remote-build.nix` (TOML → `builders = "@<store toml>"`).
- This repo: `docs/lix-caveats.md` (trusted-builder forwarding caveat),
  `modules/universal/profile/remote-builders/default.nix` (current config).
