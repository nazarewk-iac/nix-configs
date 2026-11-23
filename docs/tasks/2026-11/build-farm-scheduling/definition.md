---
type: Task
description: The build farm places builds from a connection count, not from a builder's real load; keep HAProxy and add a per-builder agent-check responder that reports `ready maxconn:N`.
status: open
authored_by: agent
timestamp: 2026-11-23T22:22:33+01:00
---

# A scheduler for the build farm, not a load balancer

## Problem

One HAProxy container on `etra` forwards SSH streams to the builders
(`modules/den/aspects/build-farm.nix`, `data/build-farm.nix`). It places a build from
`balance first` and a per-builder `maxconn` spill threshold
(`build-farm.nix:299,308`).

The proxy sees three facts per backend: the live connection count, a static
`maxConnections`, and one dynamic signal, the `kdn-build-farm-agent` `ready maxconn:N`
check on `brys` (`hosts-den/brys/llm.nix:353-412`). That agent shrinks the `brys` pool
while a frontier model is resident.

The proxy cannot see the derivation — an SSH stream is opaque. It cannot see the queue
depth behind the connections, and it cannot see whether a builder already runs the same
inputs. One derivation therefore runs once per client, and a full builder shows itself
only as refused connections.

[research.md](research.md) holds the evidence with source lines, the comparison table,
and the recommendation this task follows.

## Two options evaluated

### Option 1: `Mic92/nix-grpc-store`

A gRPC store transport with a build-farm scheduler
([Mic92/nix-grpc-store](https://github.com/Mic92/nix-grpc-store), 0.3.0-beta.6). The
scheduler places a derivation by system, features, free slots, queue age, and the last
builder of an input. It builds one derivation once for many clients and reports queue
depth. A multi-node farm adds envoy, a private CA, and one daemon per builder; a
standalone node needs none of them.

**Verdict: reject for now — the client plugin fails under Lix.** The loader resolves
exactly `libnixstore.so.<soversion>` and checks that the running Nix already maps it
(`RTLD_NOLOAD`, `plugin-loader.cc:30,36`). Lix ships `liblixstore.so`, and recent Lix
ships one merged `liblix.so`; no `libnixstore.so.<v>` exists. The project has no Lix
support anywhere: `grep -ril lix` over the source tree returns nothing, and every plugin
build links CppNix. Re-evaluate when upstream grows a Lix loader. The full gate is in
[research.md](research.md).

### Option 2: A custom `build-hook`

Nix starts `$build-hook` for a derivation its daemon cannot build locally. The hook gets
the derivation path, the system, the required features, and one bool: does the local
daemon have a free slot
(`derivation-building-goal.cc:1208-1210`). It can read the `.drv` from the local store.
It answers `# accept` with a machine name, or `# decline` / `# postpone`. The stock hook
is `nix __build-remote`.

**Verdict: do not write one yet.** It sees one derivation at a time and cannot see a
remote builder's queue, a build another client started, or which builder holds the
inputs. Derivation-aware placement therefore needs a shared state service that the hook
fetches from — the queue state the farm does not have. A defect runs as root inside
every client's `nix-daemon` and can stop all remote builds on that machine.

## Chosen direction

Keep HAProxy. Add a real agent-check responder per builder, in the style of the `brys`
check that already works: each builder answers `ready maxconn:N` from its own load, on
the `probePort` mechanism that already exists (`build-farm.nix:316`). The existing spill
mechanism then follows real load instead of a static number.

- It replaces: the static `maxConnections` values (`data/build-farm.nix:33,55`) and the
  one-off nature of the `brys` agent script; `hosts-den/brys/llm.nix:353-412` becomes one
  instance of a general mechanism.
- It does not touch: the SSH transport, the ports and pools, the machines file, the socat
  forward to the Rosetta VM, or the client switch `build-farm-brys`.
- It cannot: see a derivation, dedup a build across clients, or place by features.

## Open questions

1. Does `nix-grpc-daemon` work when the host's own `nix-daemon` is Lix? The gRPC layer
   tunnels the CppNix worker protocol; untested against Lix here.
2. Would upstream accept a Lix soname in `plugin-loader.cc`? That one change reopens
   option 1; it needs an issue, not a fork.
3. Can a hook process override `builders` through the environment, so it delegates
   placement to the stock hook?
4. How many builds does the farm run per day? Dedup and fairness pay off only above some
   volume; no measurement exists.
5. What load signal should a responder read — free RAM, `nix list-jobs` depth, a mix?
6. How stale may an answer be: the pool polls every 10 s (`agent-inter 10s`); is a
   crashed responder fail-open or fail-drained? (The `brys` script fails open.)

## Minimal PoC acceptance sketch

The PoC is a later change. It must not disturb the running farm:

- **One `runNixOSTest` in this repo.** One client VM, two `x86_64-linux` builder VMs,
  HAProxy in front on a test-only port, and the responder program running there.
- **Isolation.** No aarch64 VM, no qemu TCG emulation, no host activation, and no change
  to `brys`, `etra`, or `oams`. The test registers its builders nowhere outside its own
  VMs, and running it opens no connection to any real farm host.
- **End to end.** A trivial derivation builds through the endpoint from the client VM.
- **Placement.** With the responder reporting a lowered `maxconn` on builder A, a new
  build goes to builder B instead of queueing on A. This is the mechanism `brys` already
  proves for LLM shed.
- **Saturation.** With `maxconn=1` and two concurrent distinct derivations, the second
  lands on the second builder.
- **Dedup, stated honestly.** A repeated identical derivation must not build twice at
  once. Nix's own local queueing of an identical derivation on the client is part of the
  mechanism here, not a feature of the responder; the test says which one it observed.
- **Evidence.** Each acceptance point names the builder-visible evidence: the HAProxy
  agent log, the responder's own log, and the build result on the builder that ran it.

## Risks

- **The responder is only as good as its input signal.** A load metric that ignores page
  cache or a resident model misleads the pool; the `brys` history records exactly that
  trap (`hosts-den/brys/llm.nix:28-32`).
- **A wrong `maxconn` moves load the wrong way.** A too-high value overruns one builder;
  a too-low value idles it and pushes work into `timeout queue 10s` failures.
- **One trivial derivation measures nothing about volume.** The PoC proves the mechanism,
  not the gain; real build volume stays unmeasured (open question 4).
- **A drained server must come back.** The agent must answer `ready` every time; a bare
  `maxconn` never clears a drain the agent set earlier (HAProxy manual, note in
  `hosts-den/brys/llm.nix:397-408`).
- **The "away ⇒ build local" invariant.** The LAN bind and the firewall gate make it
  true today (`build-farm.nix:592-614`); any new endpoint must keep it.

## Out of scope

- Any change to a host, a module, a check, or `data/build-farm.nix` while this task is
  open. The PoC lands as its own change with its own review.
- Adopting `nix-grpc-store` or writing a custom hook. See the verdicts above.
- The binary cache. `nix-grpc-store` pairs with `niks3`; this task does not decide that.
