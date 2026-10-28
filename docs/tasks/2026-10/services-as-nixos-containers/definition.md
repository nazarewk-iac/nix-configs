---
type: Task
description: Run an auxiliary service as a confined NixOS container instead of on the host — own filesystem, own process table, private network with a narrow socat ingress — with its data bind-mounted from a persistent bucket.
status: in-progress
authored_by: agent
timestamp: 2026-10-28T12:30:00+01:00
---

# Services as NixOS containers instead of host processes

> **State 2026-10-28:** pattern established and the first instance is built
> (Prometheus on `brys`). Not yet activated.

## Why

The default in this repository is to run a service directly on the host: a
`systemd` unit, sometimes `DynamicUser`, and a set of `Protect*` / `Restrict*`
directives. That is cheap and it works, and for a service the host trusts it is
right.

It is the wrong default for a service that parses untrusted input and writes an
unbounded directory. Prometheus is exactly that: it scrapes two HTTP endpoints,
parses whatever text arrives, and appends samples forever. On the host it shares
the filesystem with the model GGUFs, the session cache (plaintext prompt tokens)
and `/run/secrets`.

The question this task answers: **what is the cheap, declarative way to confine
such a service without inventing a VM per daemon?**

Answer: `containers.<name>` from `nixos/modules/virtualisation/nixos-containers.nix`.
It is systemd-nspawn, no flake input, a handful of options, and the guest is a
normal NixOS module evaluated from the same repository.

## The pattern

Four decisions, and they are the reusable part.

### 1. Private network, with a narrow ingress

```nix
containers.prometheus = {
  privateNetwork = true;
  hostAddress = "10.233.90.1";   # the host side of the veth
  localAddress = "10.233.90.2";  # the container side
  ...
};
```

`privateNetwork = true` gives the guest one interface (the veth to the host) and
nothing else. It cannot reach the LAN, the internet, or another container.

The services it must reach stay bound to `127.0.0.1` on the host, and a **socat
relay per port** publishes exactly that port on the bridge address:

```nix
systemd.services."llm-metrics-relay-swap" = {
  serviceConfig = {
    ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39700,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:39700";
    DynamicUser = true;
    # …the usual Protect*/Restrict* set
  };
};
```

The `bind=` is what makes it an ingress rather than a hole: the listener exists
only on the container bridge, so the same port is still closed on every host
interface. Two relays mean two reachable ports, and the guest has no route to
anything else.

This is the piece to copy. "Give the container the host network" is almost always
the wrong choice: it removes the isolation the container was for.

### 2. Data on a persistent bucket, bind-mounted in

```nix
bindMounts."/var/lib/prometheus2" = {
  hostPath = "/var/lib/prometheus2";
  isReadOnly = false;
};
```

The guest sees a private path; the host mount makes it the persistent directory.
The inside and outside path names are kept the same, so a reader of either config
sees one path.

**Bucket choice matters on this repository's impermanence layout** (tmpfs root,
ZFS pool, `preservation` bind-mounts):

| Bucket | For |
|---|---|
| `sys/state` | data whose loss changes behaviour: the TSDB, the JSONL collector output |
| `sys/cache` | data that is rebuilt on demand: the **container root** |
| `usr/data` | user documents |
| `disposable` | never for anything that must survive |

Metrics are state, not cache, so the TSDB lives in `sys/state`. The container's
own writable root (`/var/lib/nixos-containers/<name>`) is rebuilt data, so it
lives in `sys/cache`; unlisted, it would be a tmpfs directory and the guest would
start with a blank root every boot.

### 3. `lib.mkIf`, not `lib.optionalAttrs`

The first version used `lib.optionalAttrs withSwap { containers.prometheus = …; }`.
That builds on the host profile and evaluates the container's `path` only when
the same expression produces it, so a **sibling specialisation** with
`inheritParentConfig = false` and `containers.prometheus.enable = false` still
walked into `containers.prometheus.path` and failed with
`The option specialisation.llm-ds4.configuration.containers.prometheus.path was
accessed but has no value defined`.

`lib.mkIf withSwap { … }` declares the option in every context and defines its
value conditionally, which is what a module system wants. A whole-host build is
the gate that catches this; an eval of one attribute does not.

### 4. The guest is an ordinary module

The container's `config` is evaluated from this repository, so it can carry the
same `stateVersion`, the same users, and its own `services.*`. No image build, no
`oci`, no registry.

## The first instance: Prometheus on `brys`

`hosts/brys/llm.nix`:

| Piece | Where |
|---|---|
| `containers.prometheus` | `privateNetwork`, `10.233.90.1/2`, `/var/lib/prometheus2` bind-mounted, `services.prometheus` inside with 30 d / 2 GB retention and two jobs |
| `systemd.services."llm-metrics-relay-swap"` | publishes `127.0.0.1:39700` (llama-swap `/metrics`) on the bridge |
| `systemd.services."llm-metrics-relay-node"` | publishes `127.0.0.1:9100` (node_exporter textfile) on the bridge |
| `services.prometheus.exporters.node` | stays on the host: it must read `/var/lib/llm-stats/*.prom`, and it needs no ingress of its own |
| `kdn.disks.persist."sys/state"` | `/var/lib/llm-stats` (0755), `/var/lib/prometheus2` (0750, `prometheus`) |
| `kdn.disks.persist."sys/cache"` | `/var/lib/nixos-containers` (0755) |

The scrape targets inside the guest are `10.233.90.1:39700` and
`10.233.90.1:9100`, because from the guest the host is the bridge address.

## When to use this, and when not to

Use a container when the service:

- parses untrusted input over the network,
- needs its own filesystem or its own users,
- writes an unbounded directory,
- would otherwise need a pile of `Protect*` that is hard to get right.

Do **not** use a container when the service:

- must read host state that is awkward to bind-mount (the model GGUFs are 100 GB
  and `mmap`ed: an LLM server belongs on the host, exactly as it is today),
- must control the host (network config, firewall, RAID),
- is latency-critical on the host's own traffic,
- would need the host network to work at all — that defeats the purpose.

## What this task does not do

- No Grafana, no reverse proxy. Those are separate decisions with their own cost.
- No migration of existing services. The task establishes the pattern and one
  instance; a later change can move another service when it has a reason.
- No container networking beyond one bridge. Overlay networking, port
  forwarding to the LAN and inter-container links are not needed yet; when one
  is, it gets its own short section here rather than an ad-hoc `--network host`.

## Acceptance

- `container@prometheus.service` exists in the built system, and the three units
  (`llm-stats`, both relays, the exporter) are present.
- The whole-host build succeeds, including a sibling specialisation with
  `inheritParentConfig = false`.
- The three persist paths are present in the parent config **and** in the
  `llms-frontier` specialisation.
- On the activated host: the container is `active`, and both scrape targets are
  `up`.
- A reboot keeps both the TSDB and the collector output.
- The relay ports are closed on every host interface and open only on the bridge.

## Verification commands

```sh
systemctl status container@prometheus llm-stats llm-metrics-relay-swap llm-metrics-relay-node
machinectl list
curl -s localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets[] | {job: .labels.job, health}'
ss -tlnp | grep -E '39700|9100|9090'      # expect 127.0.0.1 and 10.233.90.1 only
journalctl -u container@prometheus -n 30 --no-pager
tail -1 /var/lib/llm-stats/activity-$(date -u +%F).jsonl | jq .
```

## Risks

| Risk | Mitigation |
|---|---|
| A specialisation with `inheritParentConfig = false` fails on a container option | `lib.mkIf`, and always build the whole host, never one attribute |
| `privateNetwork = true` blocks a target the service needs | add a third relay, never `privateNetwork = false` |
| The container root lands in tmpfs and resets on boot | `sys/cache` persist entry, verified by eval |
| Two `socat` daemons are two more things to fail | `Restart = always`, `DynamicUser`, and a target health check in the acceptance |
| The TSDB grows past the pool | 30 d **and** 2 GB retention, both enforced |
| A future `nixpkgs` changes `containers.<name>` semantics | the whole-host build is the gate; a container change shows up there |

## Activation log, 2026-10-28 (brys)

Activated on `brys` with a direct `switch-to-configuration switch` of the built
toplevel (the flake is not on that host; `nix copy --to ssh-ng://kdn-brys
--no-check-sigs` first, because the host is a trusted user but the build is
unsigned).

**Activation found three defects that an eval cannot.** All three are now in the
pattern above; they are repeated here because they cost real time.

| Symptom | Cause | Fix |
|---|---|---|
| `llm-metrics-relay-node` failed at activation | the container bridge `10.233.90.1` did not exist yet when the relay started | `after nftables.service network-online.target` on `container@prometheus`, plus `Restart=always` on the relays |
| guest → relay timed out, host → bridge answered | `nixos-fw` input chain is `policy drop`; a veth is not in `lo`/`virbr*`/NetBird | `networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = [ 9100 39700 ]` |
| host → guest `:9090` timed out | the **guest has its own** `policy drop` firewall | `networking.firewall.allowedTCPPorts = [ 9090 ]` inside the container's `config` |

Two things this proves about the pattern:

1. **There are two firewalls.** A containerised service needs an ingress rule on
   the host *and* an accept rule inside the guest. Either one missing looks
   identical from outside: a silent timeout.
2. **`containers.<name>` exposes no `unitConfig`.** The nixpkgs module writes the
   `container@%i` unit itself, so ordering is added by overriding
   `systemd.services."container@<name>"`. That override must sit outside the
   `containers.<name>` attrset, or evaluation fails with
   `Did you mean containers.prometheus.config'.

### Verified after activation

```
container@prometheus            active
llm-stats                       active
llm-metrics-relay-swap          active
llm-metrics-relay-node          active
prometheus-node-exporter        active

$ curl -s http://10.233.90.2:9090/api/v1/targets | jq -c '.data.activeTargets[] | {job: .labels.job, health}'
{"job":"llama-swap","health":"up"}
{"job":"node","health":"up"}

$ ss -tlnp | grep -E ':(39700|9100|9090)'
127.0.0.1:39700   (llama-swap, host-only)
127.0.0.1:9100    (node_exporter, host-only)
10.233.90.1:39700 (relay, bridge only)
10.233.90.1:9100  (relay, bridge only)

$ curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9090/-/ready   # 000
$ curl -s -o /dev/null -w '%{http_code}' http://192.168.73.248:9090/-/ready  # 000
```

So the TSDB is reachable **only** from inside the container namespace and via
the bridge, which is the intended confinement.

### End-to-end path, proven

One `tiny-dumb-fast` completion, then the chain:

```
$ curl … /v1/chat/completions            -> timings.predicted_per_second 177.67
$ tail -1 /var/lib/llm-stats/activity-<today>.jsonl
  {"model":"qwen3.5-0.8b","aliases":[],"tokens_per_second":177.67,"status":200,"duration_ms":…}
$ head -2 /var/lib/llm-stats/llamaswap.prom
  llm_prompt_tokens_per_second{model="qwen3.5-0.8b",aliases=""} 236.66
  llm_tokens_per_second{model="qwen3.5-0.8b",aliases=""} 177.67
$ curl -s '10.233.90.2:9090/api/v1/query?query=llm_tokens_per_second'
  {"metric":{"instance":"10.233.90.1:9100","job":"node","model":"qwen3.5-0.8b"},
   "value":[…,"177.67399360373622"]}
```

A gap this exposed: **`aliases` is empty**. The collector resolves aliases from
`/v1/models`, which lists aliases nested under each model entry; the `jq` that
builds the map reads `.aliases`, but that endpoint returns them under a different
key for this llama-swap build. Until it is fixed, attribution is by base model id
only, and several aliases share one id. Tracked in
[../llm-metrics-persistence/definition.md](../llm-metrics-persistence/definition.md).

### Still open
- No reboot proof yet.
- `kdn-atuin-login-root` and `kdn-man-gen-caches` report failures during
  activation. Both are pre-existing and unrelated to this work; they are noted so
  a later reader does not blame the container.
