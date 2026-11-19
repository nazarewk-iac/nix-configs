---
type: Design
description: Concrete design for the six WAN shaping refinements — filter order, qdisc trees, the den aspect, the CLI contract, and the measurement plan.
task: definition.md
authored_by: agent
timestamp: 2026-11-19T12:00:00+01:00
---

# WAN shaping refinements — design

This file holds the detail behind [definition.md](definition.md). It states commands and options as
design, not as code to apply. Every tool behaviour named here has a source in the definition's
[Sources](definition.md#sources) list.

## 1. What is live, and what is weak

The module is one `oneshot` unit with an `up` and a `down` script. The weaknesses, in the order they
will bite:

| #   | observation                                                                                | why it matters                                                                                                                                                                                                                                    | fix                                                                                                                         |
| --- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 1   | The comment says "4 Mbit at 600 Mbit/s is ~0.8 ms of burst". 4 Mbit / 600 Mbit/s = 6.7 ms. | The number that sets the queue behaviour is mis-documented, so the next edit starts from a wrong model.                                                                                                                                           | Derive the burst from the rate, and state the formula in the comment.                                                       |
| 2   | `burst` is fixed at 4 Mbit.                                                                | `tc-tbf(8)` gives `rate/HZ` as the minimum burst. At 1 Gbit/s and HZ=250 that minimum is 4 Mbit, so any rate raise puts the fixed burst at the edge.                                                                                              | `burst = 2 × rate / HZ`, rounded up to a multiple of 64 KiB.                                                                |
| 3   | The match is `src_port 443` and nothing else.                                              | UDP/443 (QUIC) is unshaped; TCP/80 and bulk SSH are unshaped; the untagged LAN shares the WAN `/24`.                                                                                                                                              | Filter program in § 2.                                                                                                      |
| 4   | `after = [ "network.target" ]`.                                                            | `network.target` does not mean "the interface exists". If `tc` runs first, the unit fails and nothing retries.                                                                                                                                    | `BindsTo=` and `After=` the interface's `.device` unit (systemd creates one per network device, named from its sysfs path). |
| 5   | `modprobe ifb …                                                                            |                                                                                                                                                                                                                                                   | true`and`modprobe cls_flower …                                                                                              |     | true`. | The failure is hidden, and `pkgs.kmod`'s `modprobe` does not necessarily see the NixOS module tree. `ifb` needs a manual load; other `tc` modules load on demand. | `boot.kernelModules = [ "ifb" ]` in the aspect; drop the `modprobe` calls. |
| 6   | `ifb-shape` is a global fixed name, `rateMbit` and `iface` are `let` values.               | A second link or a second host cannot reuse it; a rate change needs a rebuild; the module ignores `kdn.networking.iface.default`.                                                                                                                 | Aspect with one link entry per WAN (§ 4).                                                                                   |
| 7   | `tc filter replace` without a handle.                                                      | A filter with no explicit handle has no stable identity to replace, so a re-run adds a second filter. It is harmless today only because the preceding `tc qdisc replace … ingress` removes the old qdisc **and its filters** (`tc(8)`, `delete`). | Keep the qdisc replace as the idempotency point, or give every filter an explicit handle. Do not remove the qdisc replace.  |
| 8   | `tbf` is one FIFO.                                                                         | One shaped flow can take all 600 Mbit/s; many shaped flows share one tail-drop queue.                                                                                                                                                             | `cake` preset for fairness and AQM (§ 5).                                                                                   |
| 9   | `tbf` has millisecond-scale burstiness above ~1 Mbit/s (`tc-tbf(8)`).                      | The shaped rate can exceed the setting on short timescales. The measured 300 Mbit setting delivered 276 Mbit/s on average, so the setting is approximate in both directions.                                                                      | Treat the setting as a target, measure the effective rate, and use `peakrate`/`minburst` or `cake` when exactness matters.  |
| 10  | The module assumes an endpoint, not a router.                                              | `etra` needs per-host classes and conntrack marks; the current match has neither.                                                                                                                                                                 | `router-lan` preset, only when `etra` gets the aspect.                                                                      |

One more point, not a defect: `tc` stores a rate as a 32-bit bps value (`tc(8)`), so the design must
reject a ceiling above 4 294 967 295 bit/s instead of wrapping it.

## 2. The filter program

The ingress qdisc on the WAN device gets an ordered program. The documented `flower` match list has no
negation, so order is the way to express one: `tc-actions(8)` defines `pass` as "return to the calling
qdisc for packet processing, and end classification of this packet", so a `pass` filter at a low
`prio` removes a flow from shaping.

```
prio  5  flower  src_ip <local range>          action pass     # one per range, per family
prio 20  flower  ip_proto tcp src_port 443     action mirred egress redirect dev ifb-<link>
prio 21  flower  ip_proto udp src_port 443     action mirred egress redirect dev ifb-<link>
prio 30  flower  ip_proto tcp src_port <bulk>  action mirred …  # only in the bulk-ssh preset
prio 100 matchall                              action pass      # explicit default, and a counter
```

The exclusion set, as source prefixes:

| family | prefix                                       | covers                                                                      |
| ------ | -------------------------------------------- | --------------------------------------------------------------------------- |
| IPv4   | `10.0.0.0/8`                                 | `pic` VLAN `10.92.0.0/24`, and any RFC 1918 ten-net                         |
| IPv4   | `172.16.0.0/12`                              | RFC 1918                                                                    |
| IPv4   | `192.168.0.0/16`                             | `192.168.73.0/24` LAN, `192.168.252.0/24` mgmt, `192.168.41.0/24` drek      |
| IPv4   | `100.64.0.0/10`                              | CGNAT (RFC 6598) and the NetBird `100.79.0.0/16` mesh, which sits inside it |
| IPv4   | `169.254.0.0/16`                             | link-local (RFC 3927)                                                       |
| IPv4   | `127.0.0.0/8`, `224.0.0.0/4`, `0.0.0.0/8`    | loopback, multicast, "this host"                                            |
| IPv6   | `fd00::/8`                                   | `fd12:ed4e:366d::/48` ULA and the `fd31::/32` mesh                          |
| IPv6   | `fe80::/10`, `ff00::/8`, `::1/128`, `::/128` | link-local, multicast, loopback, unspecified                                |

Why exclude by source and not by destination:

- `brys` is not a router. An ingress packet with a non-local source is either addressed to `brys` or
  it is dropped. So "source is not local" is the sharpest available test.
- The v4 WAN address of `brys` sits inside `192.168.73.0/24`, the same `/24` as the LAN. A
  destination-`/24` test cannot separate them; only a `/32` can, and a DHCP lease makes that stale.
- A CGNAT **WAN address** is a legitimate destination. Excluding `100.64.0.0/10` on the source side
  is safe, because no internet source is routable in that prefix. Excluding it on the destination
  side would silently disable shaping on a CGNAT uplink.

Tagged frames are a separate question. `tc-flower(8)` states that layer-3 matches depend on the
filter's `protocol` option, and it provides `vlan_ethtype` for tagged frames. A `protocol ip` filter
therefore probably does not match an 802.1Q frame, which would put the tagged VLANs outside the
program by construction. This must be measured, not assumed: run one HTTPS transfer from a tagged
VLAN host and read the `matchall` counter against the shaped counters (`tc -s filter show`).

Command sketch for the apply path:

```sh
ip link add "ifb-$link" type ifb 2>/dev/null || true
ip link set "ifb-$link" up

tc qdisc replace dev "$iface" handle ffff: ingress      # removes the old qdisc and its filters
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16 \
           127.0.0.0/8 224.0.0.0/4 0.0.0.0/8; do
  tc filter add dev "$iface" parent ffff: protocol ip prio 5 \
    flower src_ip "$net" action pass
done
for net in fd00::/8 fe80::/10 ff00::/8; do
  tc filter add dev "$iface" parent ffff: protocol ipv6 prio 5 \
    flower src_ip "$net" action pass
done

tc filter add dev "$iface" parent ffff: protocol ip prio 20 \
  flower ip_proto tcp src_port 443 action mirred egress redirect dev "ifb-$link"
tc filter add dev "$iface" parent ffff: protocol ip prio 21 \
  flower ip_proto udp src_port 443 action mirred egress redirect dev "ifb-$link"
tc filter add dev "$iface" parent ffff: protocol ipv6 prio 20 \
  flower ip_proto tcp src_port 443 action mirred egress redirect dev "ifb-$link"
tc filter add dev "$iface" parent ffff: protocol ipv6 prio 21 \
  flower ip_proto udp src_port 443 action mirred egress redirect dev "ifb-$link"

tc filter add dev "$iface" parent ffff: protocol ip prio 100 matchall action pass
tc filter add dev "$iface" parent ffff: protocol ipv6 prio 100 matchall action pass
```

Constraints that shape this program:

- `flower` needs `ip_proto` before `src_port`, and one filter can name only one `ip_proto`
  (`tc-flower(8)`). So TCP and UDP are separate filters, and an IPv4 filter cannot cover IPv6.
- `mirred` cannot redirect from one ifb to another, and nesting is limited to four levels
  (`tc-mirred(8)`). One ifb per link, direct redirect only.
- An interface name is at most 15 characters; `ifb-<link>` must fit.
- `police` is not used. `tc-police(8)` and the ArchWiki both state that ingress policing drops and
  does not queue; a queue on the ifb delays instead, which is what a shaper must do.

## 3. What counts as a shaped flow

The protocol class table is data, not code. Each row names one flow and whether the default set
includes it:

| class      | flows                                         | default set            |
| ---------- | --------------------------------------------- | ---------------------- |
| `https`    | TCP/443                                       | yes                    |
| `quic`     | UDP/443                                       | yes (first addition)   |
| `http`     | TCP/80                                        | no                     |
| `ssh-bulk` | TCP/22                                        | no (`bulk-ssh` preset) |
| `vpn`      | outer UDP of WireGuard/OpenVPN; ESP for IPsec | no                     |
| `mesh`     | outer WireGuard of `nb-*`                     | no                     |
| `unshaped` | everything else                               | the `matchall` default |

Rationale for each row:

- QUIC runs over UDP (RFC 9000) and HTTP/3 uses QUIC (RFC 9114). A browser or a `curl` with HTTP/3
  downloads unshaped today.
- TCP/22 carries both interactive sessions and bulk `rsync`/`nix copy`. Shaping it by default would
  hurt the interactive case, so it is opt-in.
- WireGuard encapsulates IP packets over UDP; the inner 5-tuple is encrypted, so inner ports cannot
  be matched. NetBird is a WireGuard-based overlay and already arrives on its own `nb-<name>`
  device, which is not the WAN device, so the mesh is outside the program. A tunnel can be capped
  only as a whole, by its outer endpoint.
- IPsec ESP has no ports; only a numeric protocol match (`ip_proto 0x32`, since `tc-flower(8)` names
  only tcp, udp, sctp, icmp, icmpv6 and l2tp) can select it.
- ICMP, DNS and NTP must never be shaped: path-MTU discovery and name resolution decide whether the
  other flows work at all.

## 4. The aspect

`modules/den/aspects/net-wan-shaping.nix`, class list `nixos`, registered in `modules/den/lib.nix`.
Inclusion is the switch (no `enable`), and every option defaults to an empty value, so an adopter
that names no link gets nothing.

```nix
{ config, lib, ... }:
let
  defaultIface = config.kdn.networking.iface.default.name;
in
{
  options.kdn.networking.wanShaping.links = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        iface = lib.mkOption {
          type = lib.types.str;
          default = defaultIface;
          defaultText = lib.literalExpression "config.kdn.networking.iface.default.name";
        };
        ifb = lib.mkOption { type = lib.types.str; default = "ifb-${name}"; };
        direction = lib.mkOption {
          type = lib.types.enum [ "ingress" "egress" "both" ];
          default = "ingress";
        };
        ceilingMbit = lib.mkOption { type = lib.types.ints.positive; };
        linkMbit = lib.mkOption { type = lib.types.ints.positive; };
        qdisc = lib.mkOption {
          type = lib.types.enum [ "tbf" "cake" "htb" ];
          default = "tbf";
        };
        preset = lib.mkOption {
          type = lib.types.enum [ "off" "bulk" "interactive" "bulk-ssh" "router-lan" "upload" ];
          default = "bulk";
        };
        burst = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
        excludedSources = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10"
                      "169.254.0.0/16" "127.0.0.0/8" "224.0.0.0/4" "0.0.0.0/8"
                      "fd00::/8" "fe80::/10" "ff00::/8" ];
        };
        flows = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "tcp/443" "udp/443" ];
        };
      };
    }));
  };
}
```

Rendered per link:

- `/etc/kdn/wan-shape/<link>.json` — the resolved config, the only input of the CLI.
- `systemd.services."kdn-wan-shape-<link>"` — `oneshot`, `RemainAfterExit`, `ExecStart`/`ExecReload`/
  `ExecStop` call `kdn-wan-shape`, `BindsTo`/`After` the interface's `.device` unit, and
  `ConditionPathExists` on a "disabled" marker if the runtime override turns it off.
- `boot.kernelModules = [ "ifb" "cls_flower" "cls_matchall" ]`, plus `sch_tbf`, `sch_cake` or
  `sch_htb` when the preset uses them. `ifb` needs the explicit load; the other `tc` modules load on
  demand, so this list is a guarantee, not a requirement.

The device unit for the dependency is `sys-subsystem-net-devices-<iface>.device`, named from the
`/sys/` path (`systemd.device(5)`). A `-` in the interface name becomes `\x2d` in the unit name
(`systemd.unit(5)`), so build the name with `lib.replaceStrings [ "-" ] [ "\\x2d" ]` instead of
writing it by hand.

The default `ifb` name uses the link key, because `ifb-shape` collides as soon as a second link
exists. Add an `assert` that `ifb` is at most 15 characters: an interface name has the `IFNAMSIZ`
limit, and `ip link add` fails on a longer name, which puts the error far from its cause.

The unit name changes from `kdn-wan-shaping` to `kdn-wan-shape-<link>`. Do the migration in one
commit, so no generation carries both units: two units that both redirect to different ifb devices
would each shape the same packets once.

## 5. Presets and qdisc trees

### `bulk` (default, `tbf`)

```sh
tc qdisc replace dev "ifb-$link" root handle 1: \
  tbf rate "${ceiling}mbit" burst "${burst_bytes}" latency 20ms
```

- `burst` is a size, not a rate: `tc(8)` lists `mbit` under SIZES as megabits, so `4mbit` means
  500 KB. Compute it in bytes and pass a byte suffix, for example `560kb`.
- `burst = 2 × ceiling / HZ`, rounded up to a multiple of 64 KiB. `tc-tbf(8)` gives `rate/HZ` as the
  minimum. At 600 Mbit/s and HZ=250 that is about 4.8 Mbit, close to today's value; at 1 Gbit/s and
  HZ=250 the minimum is already 4 Mbit, so today's fixed value would sit at the edge.
- `latency 20ms` bounds the queue at about `ceiling × 20 ms` (1.5 MB at 600 Mbit/s). Today's 40 ms
  bounds it at about 3 MB. Start at 20 ms; lower it only if the delay of shaped flows matters,
  because a queue smaller than a sender's burst loses throughput.
- `tbf` is non-work-conserving: it idles rather than send above the rate (`tc-tbf(8)`).

### `interactive` (`cake`)

```sh
tc qdisc replace dev "ifb-$link" root handle 1: \
  cake bandwidth "${ceiling}mbit" diffserv4 dual-dsthost ingress
```

- `cake` is a deficit-mode shaper with AQM and per-flow fairness, so one flow cannot take the whole
  ceiling.
- `dual-dsthost` makes the fairness per destination host, which is the right axis on an ingress
  path.
- `ingress` makes the shaper count dropped packets as transferred, because they already crossed the
  WAN (`tc-cake(8)`). This is the strongest single argument for `cake` on an ifb.
- `diffserv4` gives four tins as WRR shares, not caps (`tc-cake(8)`). Use `htb` when a hard
  per-protocol cap is required.
- `rtt` should be set from a measurement if the default `internet` (100 ms) does not match the path.

### `router-lan` (`htb`)

```sh
# root class = link ceiling, class 1:10 = protocol, 1:1010+ = one host each
tc qdisc replace dev "ifb-$link" root handle 1: htb default 1999
tc class replace dev "ifb-$link" parent 1:     classid 1:1    htb rate "${link}mbit" ceil "${link}mbit"
tc class replace dev "ifb-$link" parent 1:1   classid 1:10   htb rate 600mbit      ceil "${link}mbit"
tc class replace dev "ifb-$link" parent 1:10  classid 1:1010 htb rate 50mbit       ceil 200mbit
tc class replace dev "ifb-$link" parent 1:10  classid 1:1011 htb rate 50mbit       ceil 200mbit
tc class replace dev "ifb-$link" parent 1:     classid 1:1999 htb rate 1mbit        ceil "${link}mbit"

# 443 belongs to the protocol class; the destination host picks the per-host child
tc filter add dev "ifb-$link" parent 1: protocol ip prio 10 \
  flower ip_proto tcp src_port 443 classid 1:10
tc filter add dev "ifb-$link" parent 1:10 protocol ip prio 10 \
  flower dst_ip 192.168.73.101/32 classid 1:1010
tc filter add dev "ifb-$link" parent 1:10 protocol ip prio 20 \
  flower dst_ip 192.168.73.0/24 classid 1:1011
```

- `htb` `rate` is a floor and `ceil` is the cap (`tc-htb(8)`), so a class that must not exceed 200
  Mbit/s needs `ceil 200mbit`, not `rate 200mbit`.
- The packet is a **download**, so the server port is the source port. `dst_port 443` would match
  nothing here; `src_port 443` is the same selector that the redirect uses.
- A filter names the destination class either with `classid` (`tc-flower(8)`) or by writing the skb
  priority with `action skbedit priority` (`tc-skbedit(8)`). `classid` is the direct form for `htb`;
  `cake` reads the priority field for its tin override.
- `htb` consults the filters attached to each node as it walks down (`tc-htb(8)`), so the per-host
  filters sit on `parent 1:10`, not on the root.
- The classes live on the ifb, so classification happens after the redirect. The redirect can carry
  the classid instead (`action mirred …` plus `flowid`), which avoids a second classification pass;
  both forms are valid, and the measured cost decides.
- `etra` is a router: its ingress packets are addressed to LAN hosts, so the per-host class needs a
  mark restored from conntrack, or `dst_ip` classes (the ArchWiki `connmark` pattern).

### Combination rule

One tree, three levels: root class = link ceiling; child class = protocol; grandchild = host. A
level is optional. `tbf` and `cake` cannot carry classes, so they can be the root only when no
per-class split is needed, and otherwise they sit as the leaf of an `htb` class. That is the reason
`router-lan` uses `htb` even though `cake` gives better fairness: a classless qdisc cannot express
"this class is capped".

## 6. The CLI contract

```
kdn-wan-shape apply    [--link NAME] [--config FILE] [--dry-run] [--json]
kdn-wan-shape reload   [--link NAME] [--config FILE]
kdn-wan-shape clear    [--link NAME]
kdn-wan-shape status   [--link NAME] [--json]
kdn-wan-shape set      rate MBIT | preset NAME | flows LIST
kdn-wan-shape explain  [--link NAME]
kdn-wan-shape check    [--link NAME]
```

- `apply` is the only path that replaces the ingress qdisc, so it can leave a short window where a
  packet passes unshaped (`tc(8)` calls `replace` a "nearly atomic remove/add"). It is idempotent: a
  second run produces the same qdiscs and filters.
- `reload` uses `tc qdisc change` / `tc class change` only (`tc(8)`), so no filter is rebuilt and no
  queue is destroyed. It is the path for a rate change. It cannot change the qdisc kind, so a preset
  that swaps `tbf` for `cake` needs `apply`.
- `clear` deletes the ingress qdisc and the ifb device for that link only.
- `status` prints the qdisc, the class tree and the per-filter counters, from `tc -s qdisc` and
  `tc -s filter`.
- `check` is read-only: it verifies that the interface exists, that the module is loaded, that the
  ceiling is below the 32-bit limit, and that the exclusion set covers every local prefix of the
  host (`ip -j addr`).
- `--for 20m` (on `apply` and `set rate`) saves the current config, then runs
  `systemd-run --on-active=20m kdn-wan-shape apply --config <saved>`, so a temporary cap removes
  itself.
- Exit codes: `0` success, `1` runtime failure (no interface, `tc` error), `2` usage error. The unit
  reads the exit code, so the two cases must not be mixed.

Config file, one per link, resolved by Nix and overridable at runtime:

```json
{
  "link": "wan",
  "iface": "kdn-eth-2g",
  "ifb": "ifb-wan",
  "direction": "ingress",
  "ceilingMbit": 600,
  "linkMbit": 1000,
  "qdisc": "tbf",
  "preset": "bulk",
  "burst": null,
  "excludedSources": ["192.168.0.0/16", "100.64.0.0/10", "fd00::/8"],
  "flows": ["tcp/443", "udp/443"],
  "enabled": true
}
```

The CLI merges three layers: Nix defaults < `/etc/kdn/wan-shape/<link>.json` <
`/var/lib/kdn/wan-shape/<link>.override.json`. The override file is what `set` writes and what
survives a reboot, which is the answer to § a in the definition.

## 7. Measurement plan

Every step ends with a number. Do not accept a step on "it looks right".

| what               | command                                                                                                              | acceptance                                                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| shaped rate        | `curl -o /dev/null -w '%{speed_download}\n' <100 MB URL>`                                                            | within 10 % of `ceilingMbit / 8`                                                                                                       |
| unshaped rate      | the same `curl` with the unit stopped                                                                                | at least 95 % of the 105 MB/s baseline                                                                                                 |
| which flows match  | `tc -s filter show dev "$iface" parent ffff:`                                                                        | shaped counters rise for an internet download; the `matchall` counter rises for LAN traffic; excluded sources show zero shaped packets |
| LAN false positive | start `openssl s_server -accept 443 -www` on `brys` for one minute; fetch `https://<brys-lan-addr>/` from a LAN host | before the exclusion the shaped counter rises; after it, only the `matchall` counter rises                                             |
| queue delay        | `ping` beside a shaped download                                                                                      | added delay at or below the `latency` setting                                                                                          |
| boot               | reboot, then `systemctl status kdn-wan-shape-*`                                                                      | active without a manual restart                                                                                                        |
| reload             | `systemctl reload`, then `tc -s qdisc`                                                                               | new rate; drop counter does not jump                                                                                                   |
| temporary cap      | `kdn-wan-shape set rate 300 --for 1m`                                                                                | full rate returns after 1 minute, with no operator action                                                                              |
| upstream           | `iperf3 -c <public server> -R` or a large upload                                                                     | a number for the `upload` preset                                                                                                       |

Two traps from the existing measurements:

- `trickle` under-delivers 3x. Do not use it as a reference; measure with `curl` and `tc -s`.
- `drek` shapes but its DSA counters do not report the shaped traffic. Measure at the ends, never on
  the router.

## 8. Deliberately out of scope

- A per-cgroup budget (step 7 of the definition's ranked plan). It needs a prototype, and `net_cls`
  is a cgroup v1 controller that reads zero on a cgroup v2-only host.
- Darwin. `tc` is an iproute2 tool, so the aspect is `nixos` only.
- `drek` and OpenWrt SQM. It is a separate system with its own tooling, and the existing
  measurements show its counters cannot tune a rate.
- Any change to the router, the switch fabric or the ISP link. This task writes files only.
