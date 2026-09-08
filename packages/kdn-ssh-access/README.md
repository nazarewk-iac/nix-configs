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
The wrapper uses `--set-default`, so the precedence is `--config` first, then an exported
`$KDN_SSH_ACCESS_CONFIG`, then the baked path. Point the installed binary at another graph like
this:

```bash
kdn-ssh-access debug --config ./other-graph.json brys   # one command
KDN_SSH_ACCESS_CONFIG=./other-graph.json kdn-ssh-access debug brys
```

## Modes

```bash
kdn-ssh-access ssh [args...]        # ssh with a generated drop-in config (the `ssh-access` shim)
kdn-ssh-access proxy <host> <port>  # the ProxyCommand; not run by hand
kdn-ssh-access emit-ssh-config      # print the ssh drop-in
kdn-ssh-access route <host>         # list ranked paths, no probe, no connection
kdn-ssh-access debug [host...]      # full diagnosis, and a real session (see below)
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
kdn-ssh-access debug <host>          # checks, probes, and a real session
kdn-ssh-access debug --no-connect    # checks and probes only — no session, no tap
```

`debug` runs in four stages, and prints one line per result:

| Stage | Does |
|---|---|
| `checks` | Reads the config, validates the graph, checks `ssh` and the agent, resolves the uplinks, counts the cached verdicts |
| `routes` | Ranks the paths per host, resolves the entry addresses, probes the first hop |
| `session` | Opens a real ssh session per host and runs `true` there |
| `summary` | Counts the failures and the warnings, and names what stayed untested |

**The session runs by default**, because the first three stages stop before authentication. Only a
real session covers the auth, the host keys, and every hop after the first. `debug` prints a banner
before it starts one. The caveats:

- a session can ask for a **hardware-key tap**, one per host;
- a session **writes the reachability cache**, exactly like any other real run;
- a session **fails on an unknown host key**, because `BatchMode=yes` allows no prompt.

`debug` exits `1` when any check fails, so it works in a script.

With no host argument it covers **every** host in the graph. Name one or more hosts (a bare name or
a full `kdn-name+tag` spec) to narrow the run.

| Flag | Effect |
|---|---|
| `--no-connect` | Skip the session. Checks and probes only, and no tap |
| `--config-only` | Static checks only — no probe and no session. Offline and instant. `--no-probe` is an alias |
| `--clear-cache` | Delete every cached reachability verdict for the current network first |
| `--timeout <ms>` | Override `defaults.lanProbeTimeoutMs` for the probes |
| `--connect-timeout <s>` | Deadline per session (30 s by default) |
| `-v` / `--verbose` / `--details` | Add one level of detail. Repeat it: `-vv`, `-vvv` |

Use `--config-only` after a config change, when offline, or when the probes are too slow to wait
for. Use `--no-connect` when you cannot tap the token.

## Detail levels

The default output is a summary. Each level adds to it:

| Level | Adds |
|---|---|
| (default) | One line per check, one line per host route, one line per session, the summary |
| `-v` | The `defaults`, the resolved paths of the binaries and the addresses, the ranked path list per host, the ssh command line |
| `-vv` | Each probe with its timing, the cached verdicts, the paths that the tags drop, the `Host kdnhopN` stanzas of a chain, and ssh's own stderr |
| `-vvv` | Passes `-v` to ssh, so its full handshake goes to the trace |

A line where ssh asks you for something — a hardware-key tap, a PIN, a passphrase — always passes
through live, at every level. One case escapes that: when the **agent** holds a touch-required key,
the agent signs in its own process, so its "Confirm user presence" line never reaches `debug`. A tap
wait is therefore silent, and a session that runs longer than 2 s prints a note of its own instead.

## Example output

```
== checks ==
  ok    config    6 host(s), 1 uplink(s) — /nix/store/….json
  ok    graph     all 6 host(s) have valid edges and a path from me
  ok    env       ssh ok, net 172_28_91_33, agent 1 key(s)
  ok    uplinks   home: ipv6 2001:db8::2, ipv4 198.51.100.7
        cache     2 verdict(s) for this network, 0 for other networks (ttl 30s)

== routes ==
  ok    myhost    path 2/3  me -> relay(internet) -> myhost(relay)  (prio 60, 2 hops, entry 198.51.100.7:22)

== session ==
        A real ssh session to 1 host(s), each running `true` on arrival. Every session:
          - can ask for a hardware-key tap;
          - writes the reachability cache, like any real run;
          - fails on an unknown host key, because BatchMode allows no prompt.
        Opt out with:
          --no-connect     static checks and TCP probes only — no session, no tap
          --config-only    static checks only — offline and instant
          debug <host>...  narrow the run to the hosts you name
  ok    myhost    session ok in 1.42s, `true` exited 0 — ssh used chain me -> relay(internet) -> myhost(relay)

== summary ==
        1 host(s) in scope, 0 failure(s), 0 warning(s)
```

The `routes` line names the path a real run selects. The `session` line names the path ssh
**really** took: the session runs the true `ProxyCommand`, which records its route into the file
that `$KDN_SSH_ACCESS_ROUTE_FILE` names. (ssh sends the `ProxyCommand` stderr to `/dev/null` unless
ssh itself runs verbose, so a log line cannot carry that fact.) When the two lines disagree, the
cache changed between the two stages.

`debug` walks every path, not only the winner, so `-vv` also tells you whether a fallback works.

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

`debug -vvv` traces the session it opens itself. To trace a command of your own, set the
environment variable:

```bash
KDN_SSH_ACCESS_DEBUG=1 ssh kdn-myhost
```

Every internal step then goes to stderr: cache hits, dial results, the selected route, and the
full `ssh … -W …` command of a chain. Add `-vvv` to see ssh's own view:

```bash
KDN_SSH_ACCESS_DEBUG=1 ssh -vvv kdn-myhost
```

## Failures the session catches

The first three stages stop before authentication, so these need the session — or a manual
`KDN_SSH_ACCESS_DEBUG=1 ssh -vvv`. `debug` prints a hint next to each of them:

| Symptom | Likely cause |
|---|---|
| `Host key verification failed` | A `hostKeyAlias` change, or one alias reused for two hosts. Compare `emit-ssh-config` against `~/.ssh/known_hosts` |
| `Permission denied (publickey)` | Wrong `user` for that host, or the agent holds no accepted key |
| The entry hop connects, then the chain fails | A later relay edge has a wrong `address` — that name resolves **on the relay**, so test it there |
| A hardware token never prompts | `SSH_AUTH_SOCK` points at an agent without the resident key |

## Quick checklist

```bash
kdn-ssh-access debug                      # every host: checks, probes, and a real session
kdn-ssh-access debug <host>               # narrow it to one host (one tap)
kdn-ssh-access debug --no-connect         # no session and no tap
kdn-ssh-access debug --config-only        # static checks only, offline and instant
kdn-ssh-access debug -vv <host>           # add the probes, the stanzas, and ssh's stderr
kdn-ssh-access debug --clear-cache <host> # after a network change
kdn-ssh-access route <host>               # ranked paths only, no probe
kdn-ssh-access emit-ssh-config            # what ssh actually reads
KDN_SSH_ACCESS_DEBUG=1 ssh -vvv kdn-<host>   # trace a command of your own
```
