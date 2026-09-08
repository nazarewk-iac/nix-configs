---
type: README
description: Topology-aware ssh access dispatcher — host connectivity graph, ProxyCommand chains, and the debug mode.
timestamp: 2026-09-08T10:17:29Z
---

# kdn-ssh-access

A topology-aware ssh dispatcher. Each host declares **how other places reach it**. The tool then
finds a path from the current machine to the target, and either dials the target directly or builds
an `ssh` ProxyJump chain.

You do not select a route. You run `ssh kdn-<host>` and the dispatcher selects one.

## Mental model

A host declares `reachedFrom` edges. Each edge names an origin:

| `from` | Meaning | Address field |
|---|---|---|
| `internet` | An entry point, reachable from anywhere | `uplink` (a WAN address) or a literal |
| `lan` | Direct, and only when the machine is on that LAN | `address` / `addressFile` |
| `<host>` | A relay hop; the address is the target **as that relay sees it** | `address` / `addressFile` |

A relay address is resolved **on the relay**, not locally. A NetBird name or a private LAN IP is
therefore a valid relay address. No local overlay is needed.

To connect, the dispatcher:

1. Finds all paths `me -> target` (up to `defaults.maxHops`).
2. Ranks them by the sum of the edge priorities; a lower sum wins. Hop count breaks a tie.
3. Walks the ranked paths and takes the first one whose **entry address answers on TCP**.
4. For a 1-edge path it pipes the connection it just opened. For a longer path it writes a
   temporary ssh config with one `Host kdnhopN` stanza per relay and runs `ssh -W <target> <lastHop>`.

Only the **first (local) hop** is probed. Every later hop is resolved by ssh on the hop before it.

## Configuration

The option schema lives in [`module.nix`](module.nix) — read it for the authoritative field list.
Three ways to use it:

| Use | Entry point |
|---|---|
| Embed the schema in a NixOS/HM config | `pkgs.kdn.kdn-ssh-access.configType` |
| Build a validated, config-baked binary | `pkgs.kdn.kdn-ssh-access.withModule { … }` |
| Whole-machine wiring | the `kdn.ssh-access` slot (`modules/slots/ssh-access`) |

The slot installs `~/.ssh/config.d/40-kdn-ssh-access.config` and puts the binary on `PATH`. The
binary is the single source of that drop-in (`emit-ssh-config`).

At run time the config comes from `--config <file>` or `$KDN_SSH_ACCESS_CONFIG`. The configured
package bakes the latter into a wrapper, so an installed `kdn-ssh-access` needs no `--config`.

## Modes

```bash
kdn-ssh-access ssh [args...]        # ssh with a generated drop-in config (the `ssh-access` shim)
kdn-ssh-access proxy <host> <port>  # the ProxyCommand; not run by hand
kdn-ssh-access emit-ssh-config      # print the ssh drop-in
kdn-ssh-access route <host>         # list ranked paths, no probe, no connection
kdn-ssh-access debug [host...]      # full diagnosis (see below)
```

## Host spec and tags

The ssh alias is `kdn-<name>`, with optional `+tag` suffixes:

| Tag | Effect |
|---|---|
| `+direct` | Keep only LAN-origin paths |
| `+remote` | Keep only internet-origin paths (a WAN entry or a relay chain) |
| `+via=<host>` | Keep only paths through that relay |
| `+4` / `+6` | Force an address family. It filters IP literals only — a hostname always passes, because its family is unknown until the hop that dials it resolves it |

```bash
ssh kdn-myhost           # let the dispatcher select
ssh kdn-myhost+direct    # fail rather than go over the internet
ssh kdn-myhost+via=relay # force a specific relay
```

# Debugging

## Start with `debug`

```bash
kdn-ssh-access debug <host>
```

`debug` **opens no ssh session and authenticates nothing**. It only reads the config, resolves
addresses, runs `ssh-add -l`, and makes raw TCP connects. A hardware token therefore needs **no
tap** for a debug run. It also **does not write** the reachability cache, so it cannot change what
the next real run sees.

It exits `1` when any check fails, so it works in a script.

**A reachability test is the default.** With no host argument it tests **every** host in the graph.
Name one or more hosts (a bare name or a full `kdn-name+tag` spec) to narrow the test.

| Flag | Effect |
|---|---|
| `--clear-cache` | Delete every cached reachability verdict for the current network first |
| `--config-only` | Static checks only — no TCP probe. Offline and instant. `--no-probe` is an alias |
| `--timeout <ms>` | Override `defaults.lanProbeTimeoutMs` for the probes |

Use `--config-only` after a config change, when offline, or when the probes are too slow to wait
for. Everything except the probe still runs, so the graph and address checks stay in effect.

## What `debug` reports

| Section | Catches |
|---|---|
| `config` | Wrong `--config` path, a parse failure, an empty host set, unexpected defaults |
| `graph` | An invalid `from`, an edge with no address, `uplink` on a non-internet edge, an unknown uplink name, a host with no edges, a host with no path from `me` (often `maxHops` too low) |
| `environment` | `ssh` not on `PATH`, no network at all, an unset or dead `SSH_AUTH_SOCK`, an empty agent, a missing `identityFile` |
| `uplinks` | A missing or empty WAN address file, an uplink with no address — the usual cause of an unexplained "no reachable route" |
| `reachability cache` | Verdict counts for this network and for others |
| `host <name>` | Which paths the tags drop and why, address resolution per path, a live probe of each entry address, the exact ssh stanzas a chain would use, and the path a real run selects |

The last line of a host section names the selected path. That answers both "why did it take that
route" and "why did nothing work".

## Per-host output

```
== host myhost ==
        spec: host=myhost direct=false remote=false via="" family=""
        dropped: me -> myhost(lan)  (+remote needs an internet-origin path)
  ok    2 path(s) kept of 3
        1. [prio  10, 1 hop] direct me -> myhost(lan)
          probe myhost.lan.example.:22 -> unreachable after 1.001s: lookup ...: i/o timeout
        2. [prio  60, 2 hop] chain  me -> relay(internet) -> myhost(relay)
          probe [2001:db8::2]:22 -> unreachable after 1.1ms: connect: no route to host
          probe 198.51.100.7:22 -> ok in 25ms
          would run: ssh -F <tmp> -o ConnectTimeout=5 -W myhost.lan.example.:22 kdnhop0
            | Host kdnhop0
            |     HostName 198.51.100.7
            |     Port 22
            |     IdentityAgent SSH_AUTH_SOCK
            |     User kdn
            |     HostKeyAlias relay
  ok    a real run selects path 2: me -> relay(internet) -> myhost(relay)
```

`debug` probes every path, not only the winner, so it also tells you whether a fallback works.

## The reachability cache

One `ssh`, `scp`, or `git` command starts many `ProxyCommand` processes. Each is a fresh process,
so the TCP verdicts are shared through files under:

```
${XDG_RUNTIME_DIR:-$TMPDIR}/kdn-ssh-access/reach/<net-fingerprint>_<address>
```

- The TTL is `defaults.cacheTtlSeconds` (30 s by default).
- The key includes a **network fingerprint** — the local source address the routing table selects
  for a default route. A network change (VPN up or down, another WiFi) therefore never reuses an
  old verdict.
- Only first-hop addresses are cached. Relay edges are declared, not probed.

**The one trap:** a *fresh negative* verdict makes a real run skip an address with no dial. The
address can answer again while the verdict still says unreachable. This is the "debug says ok but
ssh still fails" case, and `debug` prints an explicit warning for it. Clear the cache:

```bash
kdn-ssh-access debug --clear-cache <host>
```

## Verbose trace of a real run

`debug` explains the decision. To watch an actual connection, set the environment variable:

```bash
KDN_SSH_ACCESS_DEBUG=1 ssh kdn-myhost
```

Every internal step then goes to stderr: cache hits, dial results, the selected route, and the
full `ssh … -W …` command of a chain. Add `-vvv` to see ssh's own view:

```bash
KDN_SSH_ACCESS_DEBUG=1 ssh -vvv kdn-myhost
```

## Failures that `debug` cannot see

`debug` stops before authentication, so these stay invisible to it. Reach for
`KDN_SSH_ACCESS_DEBUG=1 ssh -vvv` instead:

| Symptom | Likely cause |
|---|---|
| `Host key verification failed` | A `hostKeyAlias` change, or one alias reused for two hosts. Compare `emit-ssh-config` against `~/.ssh/known_hosts` |
| `Permission denied (publickey)` | Wrong `user` for that host, or the agent holds no accepted key |
| The entry hop connects, then the chain fails | A later relay edge has a wrong `address` — that name resolves **on the relay**, so test it there |
| A hardware token never prompts | `SSH_AUTH_SOCK` points at an agent without the resident key |

## Quick checklist

```bash
kdn-ssh-access debug                      # reachability test of every host (the default)
kdn-ssh-access debug <host>               # narrow it to one host
kdn-ssh-access debug --config-only        # static checks only, offline and instant
kdn-ssh-access debug --clear-cache <host> # after a network change
kdn-ssh-access route <host>               # ranked paths only, no probe
kdn-ssh-access emit-ssh-config            # what ssh actually reads
KDN_SSH_ACCESS_DEBUG=1 ssh -vvv kdn-<host>   # a real connection, fully traced
```
