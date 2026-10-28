---
type: Reference
description: How to run an auxiliary service as a confined NixOS container on these hosts — the four decisions that make it work, the traps that only appear at activation, and the verification commands.
timestamp: 2026-10-28T13:10:00+01:00
authored_by: agent
---

# Running a service as a NixOS container

The default in this repository is a `systemd` unit on the host, hardened with
`Protect*` and `Restrict*`. That is right for a service the host trusts. It is
wrong for one that parses untrusted input over the network and writes an
unbounded directory. Prometheus is that service: it scrapes two HTTP endpoints and
appends samples forever, sharing a filesystem with the model GGUFs, the session
cache (plaintext prompt tokens) and `/run/secrets`.

`containers.<name>` is the cheap confinement: `systemd-nspawn`, no flake input, a
few options, and the guest is an ordinary NixOS module from this repository. The
first instance is Prometheus on `brys` (`hosts/brys/llm.nix`).

## The four decisions

### 1. Private network with a narrow socat ingress

```nix
containers.prometheus = {
  privateNetwork = true;
  hostAddress = "10.233.90.1";   # host side of the veth
  localAddress = "10.233.90.2";  # container side
};
```

`privateNetwork = true` gives the guest one interface, the veth, and nothing else.
It cannot reach the LAN, the internet, or another container.

Host services stay bound to `127.0.0.1`, and **one socat relay per port**
publishes exactly that port on the bridge:

```nix
systemd.services."llm-metrics-relay-swap" = lib.mkIf withSwap {
  wantedBy = [ "multi-user.target" ];
  after = [ "llama-swap.service" ];
  wants = [ "llama-swap.service" ];
  serviceConfig = {
    ExecStart = "${pkgs.socat}/bin/socat -d TCP-LISTEN:39700,bind=10.233.90.1,fork,reuseaddr TCP:127.0.0.1:39700";
    Restart = "always";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    DynamicUser = true;
  };
};
```

`bind=10.233.90.1` is what makes this an *ingress* rather than a hole: the
listener exists only on the bridge, so the port stays closed on every host
interface. Check with `ss -tlnp` — you should see `127.0.0.1:PORT` for the
service and `10.233.90.1:PORT` for the relay, and nothing else.

**Do not** set `privateNetwork = false` to reach another service. Add a relay.
Sharing the host network removes the isolation the container was for.

### 2. Data on a persistent bucket, bind-mounted in

```nix
bindMounts."/var/lib/prometheus2" = {
  hostPath = "/var/lib/prometheus2";
  isReadOnly = false;
};
```

Keep the inside and outside path names identical, so a reader of either config
sees one path.

On the impermanence layout (tmpfs root, ZFS pool, `preservation` bind-mounts):

| Bucket | Holds | Example |
|---|---|---|
| `sys/state` | data whose loss changes behaviour | the TSDB, a collector's JSONL |
| `sys/cache` | data rebuilt on demand | **the container root** |
| `usr/data` | user documents | model files under `/var/lib/kdn/llms/models` |
| `disposable` | never anything that must survive | — |

The container root (`/var/lib/nixos-containers/<name>`) is rebuilt data, so it
goes in `sys/cache`. Unlisted, it is a tmpfs directory and the guest boots with a
blank root every time.

```nix
kdn.disks.persist."sys/cache".directories = [ { directory = "/var/lib/nixos-containers"; mode = "0755"; } ];
kdn.disks.persist."sys/state".directories = [
  { directory = "/var/lib/prometheus2"; mode = "0750"; user = "prometheus"; group = "prometheus"; }
];
```

### 3. There are **two** firewalls

This is the trap that costs the most time, because both failures look identical
from outside: a silent timeout.

A containerised service needs an ingress rule on the host **and** an accept rule
inside the guest.

```nix
# host: let the guest reach the relays across the veth.
networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = [ 9100 39700 ];

# inside the container: let the host reach the service.
config = { ... }: {
  networking.firewall = { enable = true; allowedTCPPorts = [ 9090 ]; };
};
```

`nixos-fw` has `policy drop` and trusts only `lo`, `virbr*` and NetBird. A veth
(`ve-<container>`) is none of them.

### 4. `lib.mkIf`, not `lib.optionalAttrs`

`lib.optionalAttrs cond { containers.x = …; }` builds on the host profile and
evaluates the container's `path` only where the same expression produces it. A
sibling specialisation with `inheritParentConfig = false` and
`containers.x.enable = false` still walks into `containers.x.path` and fails:

```
The option `specialisation.<name>.configuration.containers.x.path' was accessed
but has no value defined.
```

`lib.mkIf cond { … }` declares the option in every context and defines its value
conditionally, which is what the module system expects.

**Always build the whole host, never a single attribute.** `nix eval` of one
option does not exercise a sibling specialisation; `nix build
.config.system.build.toplevel` does.

## Ordering: the container unit is generated

`containers.<name>` exposes no `unitConfig`. The nixpkgs module writes the
`container@%i` unit itself, so ordering is added by overriding that unit **outside**
the `containers.<name>` attrset:

```nix
systemd.services."container@prometheus" = lib.mkIf withSwap {
  after = [ "nftables.service" "network-online.target" ];
  wants = [ "network-online.target" ];
};
```

Why it matters: `container@prometheus` sorts before `nftables.service`, so without
this the guest boots before the host has a rule to let it reach the relays. The
observable symptom is asymmetric: the bridge answers **from the host** but not
**from inside the guest**.

Putting `unitConfig` *inside* `containers.<name>` fails evaluation with
`Did you mean containers.prometheus.config?`.

## Verification

```sh
systemctl is-active container@<name> <each host-side unit>
machinectl list                              # the guest, its OS and address

# reachability, direction by direction
curl -s -o /dev/null -w '%{http_code}\n' http://10.233.90.2:9090/-/ready   # host -> guest
sudo -n nsenter -t "$(sudo -n machinectl show -p Leader prometheus --value)" -n \
  curl -s -o /dev/null -w '%{http_code}\n' http://10.233.90.1:39700/metrics # guest -> relay

# confinement: nothing but the bridge
ss -tlnp | grep -E ':(39700|9100|9090)'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9090/-/ready           # expect 000
curl -s -o /dev/null -w '%{http_code}\n' http://<lan-ip>:9090/-/ready            # expect 000
```

## Activating a host that has no checkout of this repository

`nixos-rebuild switch --flake .#brys` fails on `brys`: it has no clone of this
repository. Build where the flake lives, copy the closure, switch:

```sh
T=$(nix build --print-out-paths '.#nixosConfigurations.<host>.config.system.build.toplevel')
nix copy --to ssh-ng://<host> --no-check-sigs "$T"
ssh <host> "sudo -n $T/bin/switch-to-configuration switch"
```

`--no-check-sigs` is required because the build is unsigned; the host trusts the
user as a `trusted-user` in `nix.conf`, so the copy is allowed. A plain `nix copy
--to ssh://…` fails with `could not set permissions on
/nix/var/nix/profiles/per-user`.

The whole-host build takes several minutes per run on these machines.

## When to use a container

Use one when the service:

- parses untrusted input over the network,
- needs its own filesystem or users,
- writes an unbounded directory,
- would otherwise need a `Protect*` set that is hard to get right.

Do **not** use one when the service:

- reads host state that is awkward to mount — the model GGUFs are ~100 GB and
  `mmap`ed, so an LLM server belongs on the host, as it is today;
- controls the host (network, firewall, disks);
- is latency-critical on the host's own traffic;
- would need the host network to function, which defeats the purpose.

## Pre-existing activation noise on `brys`

Seen during these activations and **not** caused by the container work; noted so a
later reader does not blame it:

- `kdn-man-gen-caches.service` — *"Unit … not found"*, the activation snippet
  fails. Harmless: `mandb` runs later.
- `kdn-atuin-login-root.service` — fails on a missing atuin key. Pre-existing.
