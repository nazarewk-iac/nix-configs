---
type: Research
description: Evidence on the build farm's scheduling input today, on nix-grpc-store, and on a custom build hook, with source lines; includes the Lix compatibility gate.
task: definition.md
authored_by: agent
timestamp: 2026-11-23T23:11:25+01:00
---

# Research: build farm scheduling

## Method and sources

I read files. I ran no build and no host command. Paths and lines:

- This repo: `modules/den/aspects/build-farm.nix`, `data/build-farm.nix`,
  `hosts-den/brys/llm.nix`, `hosts/anji/default.nix`, `modules/universal/default.nix`.
- `/tmp/opencode/buildfarm-handoff.md` — facts a prior session verified. I reused them and cite
  "the handoff" where I did not re-check.
- `nix-grpc-store` 0.3.0-beta.6 (`/tmp/ngs/nix-grpc-store/.version`), a shallow clone (56 commits).
  I cite paths inside that clone, for example `src/daemon/scheduler.hh:561`. Repo facts from
  `/tmp/gh-repo.json`: MIT, 75 stars, 4 open issues, created 2026-07-09, pushed 2026-11-23.
- Lix source `/nix/store/6gkh84mmbfcrgkkp4ky6jc2qrnd3a8nc-source` (`.version` 2.35.3). The repo
  installs `lixPackageSets.latest` (`modules/universal/default.nix:124-133`); the local store holds
  `lix-2.93.2` and `lix-2.95.3`. I checked every build-hook claim against that source tree, so its
  line numbers beat the handoff's upstream numbers.

Not verified: whether nixpkgs packages `nix-grpc-store` (the GitHub contents API refused my
anonymous request); the wire compatibility of a `nix-grpc-daemon` builder against Lix's
`nix-daemon`; the full upstream commit count (the clone is shallow).

## Today's farm

One HAProxy container on `etra` forwards SSH streams to builders
(`modules/den/aspects/build-farm.nix`). Its full scheduling input is:

- One listener per system set: `x86` 2222, `arm` 2223, `darwin` 2224
  (`data/build-farm.nix:66,71,82`; frontend at `build-farm.nix:293-294`).
- `balance first` and a per-builder `maxconn` as the spill threshold
  (`build-farm.nix:299,312`). `timeout queue 10s` bounds the wait once every server is full
  (`build-farm.nix:300-303`); `maxqueue 2` caps it (`build-farm.nix:308`).
- A TCP health check that only matches the SSH banner (`build-farm.nix:342-343`).
- One dynamic signal: `kdn-build-farm-agent` on `brys`, port 39701
  (`hosts-den/brys/llm.nix:353,369`). It answers `ready maxconn:N`, where N follows free RAM on a
  linear curve (3 GiB → 1 slot, 30 GiB → 12 slots; `hosts-den/brys/llm.nix:28-32,388-395,409`).
  `brys` also caps at `maxConnections = 12` (`data/build-farm.nix:33`).

HAProxy cannot see: the derivation (an SSH stream is opaque), whether two clients want the same
drv, per-queue depth beyond the connection count, or the required system features. Features sit in
the client-side machines line only (`build-farm.nix:373-375`). One drv therefore runs once per
client, and a full builder is visible only as refused connections. The client list is a file the
daemon re-reads, `nix.settings.builders = "@/run/kdn/nix-machines"` (`build-farm.nix:622`), and the
`build-farm-brys` switch rewrites it. The proxy forces `StrictHostKeyChecking no` on one name per
pool (`build-farm.nix:393-396`). `anji-arm` is a socat forward to the Rosetta VM
(`hosts/anji/default.nix:605`, `data/build-farm.nix:48-55`).

## Option 1: nix-grpc-store

**What it is.** A gRPC transport for the Nix store plus a build-farm scheduler
(`README.md:1-40`). `Status: Stable.` (`README.md:3`). Version 0.3.0-beta.6. One
`nix-grpc-daemon` per node runs two roles: builder, and scheduler ("One scheduler is active at a
time", `docs/farm.md:18-21`). Clients use a store plugin and a `grpc://` address
(`nixos/client.nix:50` sets `nix.settings.plugin-files`; `README.md:147-149`).

**What the scheduler schedules on** (`src/daemon/scheduler.hh`):

- A queue and a free-slot index per system: `std::unordered_map<std::string, SystemState> systems`
  (1234), where "A worker sits in each of its systems' index" (1231-1232).
- Placement facts: `Entry { drvPath, inputs "for locality only", system, features, followers }`
  (561-566); `Worker { systems (vector), maxJobs, draining }` (582-589). Features must match:
  `offers()` requires the system and every feature (1502-1507).
- Free slots: `wkr.maxJobs - running` (1490). `maxJobs` arrives in the worker's `Hello` (876) and
  is a start-time setting (`docs/farm.md` `maxJobs` option).
- Order: `prio() = -(cpHint + faninWeight*followers - ageWeight*enqMs)` (1496-1500) — longest
  chain first, age as fairness. A fairness comment sits at 194-204: the next drv comes from the
  client with the fewest builds waiting. `pick()` takes the emptiest fitting worker, then prefers
  the one that built an input last (`lastBuilder`, 1236-1238, 1565-1585).
- Dedup: one `Entry` per drv path; extra clients become `followers` (`want()`, 703-714). "each
  derivation is built once even if several clients ask for it" (`docs/farm.md:3-5`); "A second
  client for a build that is already running attaches to it" (`docs/farm.md:46`;
  `src/daemon/builder.hh:92`).
- Queue depth is reported: per-system queued and free metrics (`src/daemon/dispatcher.cc:444-458`;
  `README.md:454-455`).

**Heterogeneity.** One endpoint can front the mixed fleet, but only through envoy: the client
stamps `x-nix-system` and `x-nix-features` on each call (`src/client/build.cc:63-64`) and envoy
routes on that header (`nixos/lb.nix:233`; `docs/farm.md:48-51`). A worker may list several
systems; `extra-platforms` (Rosetta, binfmt) are first-class (`docs/farm.md:157-160`). Darwin is a
supported daemon role (`flake.nix:156` `darwinModules.default`, launchd at `nixos/darwin.nix:49`).
Envoy is needed for a multi-node farm; a standalone node "schedules onto itself" with no balancer
and no niks3 (`docs/farm.md:25-27,80`).

**What a client needs.** The plugin, one build per supported Nix version
(`nix/packages/default.nix:163`), loaded into the running Nix (see the gate below).
**What a builder needs.** One daemon
(systemd; socket activation when `idleTimeout` is set, `nixos/daemon-unit.nix:12-41`), mTLS with a
private CA for the multi-node farm (`docs/farm.md:84-100`), and — in the documented design — an
S3 cache through niks3 (`docs/farm.md:78-80`).

**No RAM admission control.** A builder's `Unavailable` reasons are only `stopping`, `lowDisk`,
`localDaemonDown` (`src/daemon/builder.hh:120-136`). Nothing accepts an external memory signal at
run time. The `brys` curve has no replacement inside this project (the handoff states the same).

**Maturity.** New: created 2026-07-09; 56 commits in the shallow clone, 45 of them by one author
(`git shortlog`); MIT; 4 open issues. No nixpkgs package found (unverified). It is a young,
single-maintainer upstream to put under a fleet.

## Option 2: a custom build hook

**The protocol** (Lix 2.35.3 source, verified here): for a drv the daemon cannot build locally,
`tryBuildHook` (`derivation-building-goal.cc:1192`) starts `$build-hook` once per daemon
(`hook-instance.cc:11-72`: stdin = commands, fd 4 = builder output) and sends one line:
`"try"`, an amWilling int (`getNrLocalBuilds() < maxBuildJobs`), `drv->platform`, the drv path, and
the required features (`derivation-building-goal.cc:1208-1210`; `worker.cc:185-187`). The hook
answers `# accept`, `# decline`, `# decline-permanently`, or `# postpone`
(`derivation-building-goal.cc:1237-1246`). On accept, the daemon reads the machine name (659),
then writes the input closure (669) and the missing output names (681), and closes the pipe.

**What the hook knows** at decision time: the drv path (it can read the `.drv` locally), the
system, the features, and whether the local daemon has a free slot. **What it cannot know**
without extra state: any remote builder's queue depth, whether another client or builder already
works on the same drv, or which builder holds the inputs. Those are exactly the four questions the
definition lists, and the hook must fetch each one itself.

**What the hook must then do.** The stock hook is `nix __build-remote`
(`worker-settings.hh:120-122`) and is 414 lines (`src/nix/build-remote/build-remote.cc`). It
parses `builders` (113), picks a machine by locked slot files and `load / speedFactor` (158-198),
answers `# accept` with the machine name (271), copies the input closure (307), builds, copies the
outputs back (398), and reports failure through the result and exit status. A custom hook repeats
all of it, or delegates: it can choose the machine and hand the rest to the stock hook. Lix still
ships the command (`build-remote.cc:412`, `RegisterLegacyCommand r_build_remote`). The stock hook
takes no "use this host" argument; a custom hook would override the `builders` setting per
process (the code reads it at 113; a `NIX_BUILDERS` override per hook process is plausible but I
did not run it — verify in the PoC).

**Fit here.** The repo already uses this mechanism: `nix.buildMachines`-style lists drive the stock
hook (`build-farm.nix:622`). A custom hook could consult a queue-aware source and still reuse the
SSH transport and the whole fleet. A defect runs inside `nix-daemon` as root; `decline-permanently`
disables the hook for the daemon's life (`derivation-building-goal.cc:1239-1242`).

## Lix compatibility gate

The client plugin will not load into Lix as shipped. Evidence:

1. The loader resolves exactly `libnixstore.so.<soversion>` (Linux) or `libnixstore.<v>.dylib`
   (macOS) and checks it is already mapped, with `RTLD_NOLOAD` (`plugin-loader.cc:25-36`). On
   mismatch it warns "no plugin build matching the loaded libnixstore" and leaves `grpc://`
   unregistered (`plugin-loader.cc:117`). Loading a second copy of the Nix libraries is what the
   loader exists to avoid (`plugin-loader.cc:6-8`).
2. Lix does not map that library. The local `lix-2.93.2` ships `lib/liblixstore.so` (SONAME
   `liblixstore.so`); `lix-2.95.3` ships one merged `lib/liblix.so` (SONAME `liblix.so`); both by
   `objdump -p`. No `libnixstore.so.<v>` exists in either.
3. `grep -ril lix` over the clone's working tree returns nothing, and every plugin build links
   CppNix components: supported versions are CppNix ≥ 2.31 with a split `nix-store` library
   (`nix/packages/default.nix:28-36`), and the daemon pins `NixOS/nix` master
   (`nix-git.json`, 2.37.0-pre). Nothing tries to match a Lix soname.

Verdict: **Option 1 fails on the client side under Lix unless upstream adds a Lix loader.** The
server side is not blocked by this gate, but the gRPC layer "is a thin tunnel to the `nix-daemon`
on the other side" (`README.md:37-38`), and builds run in the host's `nix-daemon.service`
(`docs/farm.md:173`). The tunnel speaks the CppNix worker protocol (`nix-compat.hh` handles the
2.36 API moves); its interoperation with a Lix 2.95 `nix-daemon` is untested here.

The deciding experiment is small: on one Lix test machine set
`nix.settings.plugin-files` to the dispatcher bundle and run
`nix store info --store 'grpc://<node>:50051?insecure=1'`. Expected today: the 117-line warning
and an "unknown store scheme" error. A second experiment, a CppNix client (the project ships
`nix-with-plugin`, `nix/packages/default.nix:57`) against one daemon on one builder, proves the
rest of Option 1 without touching the farm.

## Comparison

| Aspect | HAProxy today | nix-grpc-store | Custom build hook |
| --- |---|---|---|
| Scheduling input | Connections per port, TCP banner, one `maxconn` scalar (`build-farm.nix:299-316`) | drv, system, features, per-system queue, free slots, input locality (`scheduler.hh:561-589,1490-1507`) | drv path, system, features, local slot (`derivation-building-goal.cc:1208-1210`); anything else costs a state service |
| Same drv, two clients | Builds twice | Builds once, second client attaches (`docs/farm.md:3-5,46`) | Possible, but the hook must keep shared state to do it |
| Heterogeneity | One port per system set (`data/build-farm.nix:66-82`) | One endpoint, envoy routes `x-nix-system` (`build.cc:63`, `lb.nix:233`) | Nix filters by `systems` client-side; the hook sees one drv at a time |
| Failure handling | `timeout queue 10s`, health check, client falls back to local (`build-farm.nix:300-303`) | Scheduler re-queues from a restarted builder; client retries with backoff (`docs/farm.md:66-77`, `README.md:391-395`) | Hook exit code; wrong choice = slow, broken hook = every remote build fails |
| brys sheds load for LLMs | Yes, `ready maxconn:N` in 10 s steps (`llm.nix:353-412`) | No memory input; only `stopping/lowDisk/localDaemonDown` (`builder.hh:120-136`) — the curve must be re-built outside | Yes, if the hook itself is the shedder, or a small state service feeds it |
| Operational cost | One container, one agent script | Daemon per builder + envoy + private CA + niks3 (`docs/farm.md:78-100`) | One root program per client; fleet unchanged |
| Client complexity | None beyond `buildMachines` rows | Plugin must match the store library — fails on Lix (gate above) | `build-hook` setting only; but root code on every client |

## What each option replaces

- **nix-grpc-store** replaces: the HAProxy container, pools and ports
  (`modules/den/aspects/build-farm.nix:291-355,528-556`, `data/build-farm.nix:15-91`), the SSH
  aliases and their `StrictHostKeyChecking no` (`build-farm.nix:389-412`), the anji socat forward
  once the Rosetta VM runs its own daemon (`hosts/anji/default.nix:600-616`), and the machines
  file (`build-farm.nix:622`). It does not replace `kdn-build-farm-agent` — it orphans it
  (`hosts-den/brys/llm.nix:353-412`), because nothing accepts a `maxconn`-style signal.
- **Custom build hook** replaces: only the placement step inside the stock hook
  (`build-remote.cc:149-235`). It can keep the proxy, the pools, the machines file, the socat
  forward, and the agent check — or drop them once it picks builders itself. It adds a root-owned
  program on every client (the `nix.settings.build-hook` setting, `worker-settings.hh:120-122`).
- **Keep HAProxy and add X** replaces: the static `maxConnections` numbers
  (`data/build-farm.nix:33,46,55`) or the single agent script; the probe machinery already exists
  (`builderType.probePort`, `build-farm.nix:71-80,316`).

## Recommendation

Keep HAProxy. Add the small half of the scheduler idea: one agent-check responder per builder,
each reporting its own load with `ready maxconn:N`, reusing the mechanism `brys` already proves
(`hosts-den/brys/llm.nix:353-412`, `data/build-farm.nix:37`). This cannot see a derivation and
cannot dedup, and it costs one script per builder plus a small per-builder load source. It fixes
the visible part of the problem — placement that follows real load, per builder, at run time.

Reject nix-grpc-store **for now** on the gate: its client plugin cannot load under Lix (three
independent facts above), and adopting it also means envoy, a CA, niks3 and a second build stack,
for a 4-month-old single-maintainer upstream. Re-evaluate when upstream grows a Lix loader; the
CppNix-box experiment above costs one machine and answers everything else.

Do not write a custom hook yet. It buys derivation awareness only by rebuilding the queue state
the farm does not have, and a defect there stops every remote build on a client. If a real need
appears — for example dedup across clients — prefer to revisit nix-grpc-store over hand-writing
the protocol.

## Open questions

1. Does `nix-grpc-daemon` (server) work when the host's own `nix-daemon` is Lix? The tunnel
   speaks the worker protocol to that daemon (`README.md:37-38`, `docs/farm.md:173`); the protocol
   compatibility with Lix 2.95 is untested here.
2. Can a hook process override `builders` through the environment, so it can delegate placement
   to the stock hook (`build-remote.cc:113` reads the setting; I could not run it)?
3. Is `nix-grpc-store` in nixpkgs? The API check failed; the flake ships its own modules, so this
   is a convenience question, not a blocker.
4. How many builds does the farm actually run per day? Dedup and fairness pay off only above some
   volume, and no measurement exists in this task.
5. Would upstream accept a Lix soname in `plugin-loader.cc`? That single change reopens Option 1;
   it needs an issue, not a fork.
