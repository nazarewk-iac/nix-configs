---
type: Design
description: NixOS side of the router shaping plan — a declarative tc setup on etra that shapes the upload on the wan bond and the download per host on the lan bond, with an optional ifb aggregate shaper, the systemd oneshot shape, the rollback path and the measurement plan.
status: open
task: definition.md
authored_by: agent
timestamp: 2026-11-19T05:40:00+01:00
---

# `etra` — the internal shaping layer

`etra` is the NixOS router between the LAN and `drek`. It does **not** know the ISP rate: it sees
a 1 Gbit/s point-to-point link to `drek` and nothing beyond it. Its job is fairness and policy —
per-host shares, a reserved class for interactive hosts, a ceiling for the host that causes
trouble — plus the aggregate download shaper when `drek` cannot hold the line rate.

Read the umbrella first: [definition.md](definition.md).

## Facts measured on the device (2026-11-19)

| Item                     | Value                                                                                                                     | Command                                   |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| CPU                      | Intel Pentium Silver N6005 @ 2.00 GHz, 4 cores, no AVX2                                                                   | `lscpu`, `/proc/cpuinfo`                  |
| RAM                      | 31.8 GB total, ~15.5 GB available                                                                                         | `free -m`                                 |
| Kernel                   | 6.18.45                                                                                                                   | `uname -r`                                |
| `tc`                     | 7.2.0 (full `iproute2` build)                                                                                             | `tc -V`                                   |
| Modules                  | `sch_cake`, `sch_htb`, `sch_ingress`, `ifb`, `act_mirred`, `cls_matchall`, `cls_flow`, `cls_fw`, `cls_flower` all present | `modinfo`                                 |
| `cake_mq`                | userspace knows the keyword, the loaded `sch_cake` does not implement it (no such string in the module)                   | `strings sch_cake.ko.xz`                  |
| `wan`                    | bond, active-backup, one slave `enp1s0`, 1000 Mb/s, `192.168.40.1/31` peer `192.168.40.0`                                 | `cat /proc/net/bonding/wan`               |
| `lan`                    | bond `802.3ad`, `enp2s0` + `enp3s0`, 2.5 Gbit/s each                                                                      | `ip -d link show lan`                     |
| Sub-interfaces           | `mgmt@lan` 192.168.252.1/24, `pic@lan` 10.92.0.1/24                                                                       | `ip -br addr`                             |
| Qdisc today              | `noqueue` on `wan` and on `lan`                                                                                           | `tc qdisc show dev wan`                   |
| Default qdisc            | `net.core.default_qdisc = fq_codel`                                                                                       | `sysctl`                                  |
| NAT                      | `IPMasquerade = "ipv4"` on the WAN network (router module)                                                                | `modules/den/aspects/net-router/base.nix` |
| Tools present            | `nstat`, `tcpdump`, `nft` system-wide; `iperf3` only in the `kdn` user profile                                            | `command -v`                              |
| TCP baseline             | `TcpRetransSegs` 63 500, `TcpExtTCPLostRetransmit` 16 610, 85 days uptime                                                 | `nstat -az`                               |
| `sqm-scripts` in nixpkgs | **not packaged**; `flent`, `irtt`, `netperf` are                                                                          | vendored nixpkgs tree                     |

Two consequences:

- There is no `services.sqm` module to reuse. `sqm-scripts` is not in nixpkgs. The setup must be
  raw `tc` in a systemd oneshot — the same shape `hosts-den/brys/wan-shaping.nix` already uses.
- `cake_mq` is not usable today. One core carries each qdisc [S1], but this core is far faster
  than the A53 on `drek`.

## Where traffic actually goes

This decides where each qdisc can live. The routing path, not preference, sets it.

| Direction            | Enters            | Leaves           | Addresses visible at that point                                   |
| -------------------- | ----------------- | ---------------- | ----------------------------------------------------------------- |
| Upload (LAN → ISP)   | `lan` ingress     | **`wan` egress** | real source, because marks are set in the forward hook before NAT |
| Download (ISP → LAN) | **`wan` ingress** | **`lan` egress** | real **destination**, because DNAT already happened in prerouting |
| Intra-LAN            | `lan` ingress     | `lan` egress     | both real                                                         |

Three rules follow:

1. **Upload shaping belongs on `wan` egress.** LAN→WAN packets never leave by `lan`, so a tree on
   `lan` cannot shape an upload.
2. **Download shaping belongs on `lan` egress.** There the packet has already been DNATed to the
   real host, and the qdisc is the last queuing point before the host.
3. **The `ifb` on `wan` ingress is for the aggregate only.** `tc` ingress runs before prerouting,
   so on that path CAKE sees the public destination and has no conntrack entry for the current
   pass [S18]. Its `nat` lookup cannot resolve a home host. Do not build per-host policy there.

Rule 3 is the one that surprises people. Test it before you rely on it: put `dual-dsthost` on the
border and check whether two downloading hosts get equal rates. In the expected result they do
not, because both flows share one destination address.

The task brief asks for "a per-source-IP HTB tree on `lan`". Read literally, that tree would shape
only traffic *toward* the LAN, where the source is a remote server — so it would shape the
download by the wrong key. This note keeps the tree but splits it by direction: source-keyed on
`wan` for the upload, destination-keyed on `lan` for the download. The tree shape, the reserved
class and the bulk cap are unchanged; only the interface and the match key move.

## Three pieces

| Piece | Where                       | Direction                | Technology                                                                       |
| ----- | --------------------------- | ------------------------ | -------------------------------------------------------------------------------- |
| A     | `wan` egress                | upload                   | HTB tree keyed by source marks, `cake` leaf for unnamed hosts                    |
| B     | `wan` ingress via `ifb4wan` | download, aggregate only | `cake … ingress` — **fallback**, see below |
| C     | `lan` egress                | download, per host       | HTB tree keyed by destination marks, `cake` leaf for unnamed hosts               |

Pieces A and C are the same tree shape on different interfaces. Only the interface and the match
key differ. Piece C is the preferred download shaper. Piece B exists for the case where the `lan`
tree cannot be used.

### A — `wan` egress: the upload tree

One tree at the shaped upload rate. The root rate **is** the shaper, so no larger root is needed:
every packet on `wan` is WAN-bound.

```
1:    htb  rate <UP>mbit  default 900
└── 1:1   htb  rate <UP>mbit  ceil <UP>mbit
    ├── 1:101  host-a   rate 25mbit  ceil <UP>mbit  prio 1     reserved
    ├── 1:102  host-b   rate 15mbit  ceil <UP>mbit  prio 2
    ├── 1:150  others   rate <UP-30>mbit  ceil <UP>mbit  prio 3 → cake leaf, dual-srchost
    └── 1:900  unmarked rate 1mbit  ceil <UP>mbit               → cake leaf, dual-srchost
```

```sh
tc qdisc replace dev wan root handle 1: htb default 900
tc class replace dev wan parent 1:    classid 1:1   htb rate ${UP}mbit ceil ${UP}mbit
tc class replace dev wan parent 1:1   classid 1:101 htb rate 25mbit ceil ${UP}mbit prio 1
tc class replace dev wan parent 1:1   classid 1:102 htb rate 15mbit ceil ${UP}mbit prio 2
tc class replace dev wan parent 1:1   classid 1:150 htb rate ${UP_MINUS_30}mbit ceil ${UP}mbit prio 3
tc class replace dev wan parent 1:1   classid 1:900 htb rate 1mbit ceil ${UP}mbit
tc qdisc replace dev wan parent 1:101 fq_codel
tc qdisc replace dev wan parent 1:102 fq_codel
tc qdisc replace dev wan parent 1:150 cake dual-srchost
tc qdisc replace dev wan parent 1:900 cake dual-srchost
tc filter replace dev wan parent 1: protocol all prio 1 handle 101 fw classid 1:101
tc filter replace dev wan parent 1: protocol all prio 1 handle 102 fw classid 1:102
tc filter replace dev wan parent 1: protocol all prio 1 handle 150 fw classid 1:150
```

- `rate` is the floor, `ceil` is the ceiling when the line has spare capacity [S2]. A single host
  can still use the whole uplink when the others are idle.
- The `cake` leaf on `1:150` takes **no** `bandwidth`. HTB shapes; the leaf only adds AQM and
  per-flow fairness. Adding a rate there would queue twice.
- `${UP}` equals `drek`'s upload setting, not more (rule 2 in the umbrella).

### B — `wan` ingress: `ifb` and CAKE in ingress mode (fallback)

Piece C already shapes the download on `lan` egress, where host addresses survive and no extra
device pass is needed. That is the preferred design. Keep B for the case where the `lan` tree
cannot be used, or when you want the queue to sit before routing.

**Do not run B and C at the same rate.** They would queue the same packets twice.

```sh
modprobe ifb
ip link add ifb4wan type ifb 2>/dev/null || true
ip link set ifb4wan up

tc qdisc replace dev wan handle ffff: ingress
tc filter replace dev wan parent ffff: protocol all prio 10 \
  matchall action mirred egress redirect dev ifb4wan

tc qdisc replace dev ifb4wan root cake \
  bandwidth ${DOWN_AGG}kbit \
  ingress \
  ethernet
```

- `matchall` redirects every packet. On `wan` everything is WAN traffic, so no selector is needed.
  `cls_matchall` is present on the device.
- `ingress` mode counts dropped packets as transferred, which is the correct accounting for a
  download shaper [S1].
- `${DOWN_AGG}` = `0.90 × measured_down`. This is the aggregate. Per-host policy is piece C.

Cost: one extra device pass per packet, on a CPU without AVX2. Measure the delivered rate before
and after. If the N6005 cannot hold the line rate here, go back to `drek` and accept a lower
aggregate.

### C — `lan` egress: the download tree

This is where the download is shared between hosts, and where a bulk host is capped. The packet
has been DNATed, so `ip daddr` is the real host.

```
1:    htb  rate 4900mbit  default 900
└── 1:1   htb  rate 4900mbit  ceil 4900mbit
    ├── 1:10  "wan-down"  rate <DOWN>mbit  ceil <DOWN>mbit
    │   ├── 1:201  host-a  rate 150mbit  ceil <DOWN>mbit  prio 1
    │   ├── 1:202  host-b  rate  60mbit  ceil <DOWN>mbit  prio 2
    │   ├── …
    │   └── 1:250  others  rate 300mbit  ceil <DOWN>mbit  prio 3 → cake, dual-dsthost
    └── 1:900  "intra-lan"  rate 1mbit  ceil 4900mbit       ← default, unshaped in practice
```

```sh
tc qdisc replace dev lan root handle 1: htb default 900
tc class replace dev lan parent 1:    classid 1:1   htb rate 4900mbit ceil 4900mbit
tc class replace dev lan parent 1:1   classid 1:10  htb rate ${DOWN}mbit ceil ${DOWN}mbit
tc class replace dev lan parent 1:10  classid 1:201 htb rate 150mbit ceil ${DOWN}mbit prio 1
tc class replace dev lan parent 1:10  classid 1:202 htb rate 60mbit ceil ${DOWN}mbit prio 2
tc class replace dev lan parent 1:10  classid 1:250 htb rate 300mbit ceil ${DOWN}mbit prio 3
tc class replace dev lan parent 1:1   classid 1:900 htb rate 1mbit ceil 4900mbit
tc qdisc replace dev lan parent 1:201 fq_codel
tc qdisc replace dev lan parent 1:202 fq_codel
tc qdisc replace dev lan parent 1:250 cake dual-dsthost
tc qdisc replace dev lan parent 1:900 fq_codel
tc filter replace dev lan parent 1: protocol all prio 1 handle 201 fw classid 1:201
tc filter replace dev lan parent 1: protocol all prio 1 handle 202 fw classid 1:202
tc filter replace dev lan parent 1: protocol all prio 1 handle 250 fw classid 1:250
```

Why this shape:

- The root `rate 4900mbit` sits under the 5 Gbit/s aggregate of the two-member bond and above the
  2.5 Gbit/s one flow can use, so the root never limits. `1:900` borrows up to 4900, so a
  host-to-host copy on the LAN does not see the WAN policy.
- `1:10` is a class that is itself shaped, so the download share is capped once and the children
  divide it [S2].
- `1:250` carries a `cake` leaf with `dual-dsthost`, so hosts without a class still get per-host
  fairness without 256 hash buckets and their collisions.

## Classification with `nft`

One table, both directions. `nft` sees the real addresses because the forward hook runs after
DNAT and before the device enqueue.

```nix
networking.nftables.tables.kdn-shaping = {
  family = "inet";
  content = ''
    chain mark-forward {
      type filter hook forward priority mangle; policy accept;

      # upload: source is the real host, before SNAT
      oifname "wan" ip saddr 192.168.73.49 meta mark set 101   # oams
      oifname "wan" ip saddr 192.168.73.4  meta mark set 102   # moak
      oifname "wan" meta mark set 150

      # download: destination is the real host, after DNAT
      iifname "wan" ip daddr 192.168.73.49 meta mark set 201   # oams
      iifname "wan" ip daddr 192.168.73.4  meta mark set 202   # moak
      iifname "wan" meta mark set 250
    }
  '';
};
```

- `oifname "wan"` matches exactly the upload; `iifname "wan"` matches exactly the download. A
  packet never matches both, so the two mark ranges cannot collide.
- Intra-LAN traffic matches neither rule, carries no mark, and falls to `default 900`. It is not
  shaped.
- IPv4 only. IPv6 falls to the catch-all classes (`150` / `250`), where the `cake` leaves still
  share fairly.
- The addresses above are examples from `data/network-topology.md` (`192.168.73.49` = `oams`,
  `192.168.73.4` = `moak`). The real list comes from the DHCP reservations in
  `hosts/etra/default.nix`.

#### Zero-configuration alternative

If the host list is not stable, `cls_flow` maps addresses to classes with no table:

```sh
tc filter replace dev lan parent 1:10 protocol ip prio 5 \
  flow map key dst addend -192.168.73.0 divisor 256 baseclass 1:300
```

`tc-flow(8)` documents exactly this form: "Map destination IPs of 192.168.0.0/24 to classids
1-256" with `key dst addend -192.168.0.0 divisor 256` [S3]. Add one filter per `/24`. It needs 256
classes and loses the host names. Prefer the static map: fewer classes, readable output.

## Composition with `drek`

| `drek` state                  | Piece A (upload tree)     | Piece C (download tree on lan) | Piece B (ifb fallback) |
| ----------------------------- | ------------------------- | ------------------------------ | ---------------------- |
| Unshaped (today)              | rate = measured up × 0.90 | parent at measured down × 0.90 | off                    |
| Shapes upload only (Option S) | rate = `drek` up (equal)  | parent at measured down × 0.90 | off                    |
| Shapes both directions        | rate = `drek` up (equal)  | parent at `drek` down (equal), shallow rates | off |

"Deep" means one class per named host plus a reserved `prio 1` host, in the `lan` tree and in the
`wan` tree. "Shallow" means a single shaped parent with a `cake` leaf and no per-host children —
the "drop the reservation depth" rule. Use shallow mode once `drek` holds latency, because CAKE's
tins already reserve at the border.

## The NixOS shape

Mirror `hosts-den/brys/wan-shaping.nix`: one `systemd` oneshot with `ExecStart`/`ExecStop`, and the
marks declared through `networking.nftables.tables` so the firewall keeps them. Proposed file:
`hosts/etra/wan-shaping.nix`, imported from `hosts/etra/default.nix`.

```nix
{
  pkgs,
  ...
}:
let
  up = 100;         # mbit, equal to drek's upload setting
  down = 400;       # mbit, equal to drek's download setting
  lanRate = 4900;   # mbit, under the 5G aggregate of the 2 x 2.5G bond

  upScript = pkgs.writeShellScript "etra-shaping-up" ''
    set -eu
    tc=${pkgs.iproute2}/bin/tc

    # A — upload tree on the wan bond
    $tc qdisc replace dev wan root handle 1: htb default 900
    $tc class replace dev wan parent 1:  classid 1:1   htb rate ${toString up}mbit ceil ${toString up}mbit
    $tc class replace dev wan parent 1:1 classid 1:150 htb rate ${toString (up - 10)}mbit ceil ${toString up}mbit prio 3
    $tc class replace dev wan parent 1:1 classid 1:900 htb rate 1mbit ceil ${toString up}mbit
    $tc qdisc replace dev wan parent 1:150 cake dual-srchost
    $tc qdisc replace dev wan parent 1:900 cake dual-srchost
    $tc filter replace dev wan parent 1: protocol all prio 1 handle 150 fw classid 1:150

    # C — download tree on the lan bond
    $tc qdisc replace dev lan root handle 1: htb default 900
    $tc class replace dev lan parent 1:  classid 1:1   htb rate ${toString lanRate}mbit ceil ${toString lanRate}mbit
    $tc class replace dev lan parent 1:1 classid 1:10  htb rate ${toString down}mbit ceil ${toString down}mbit
    $tc class replace dev lan parent 1:10 classid 1:250 htb rate ${toString (down - 100)}mbit ceil ${toString down}mbit prio 3
    $tc class replace dev lan parent 1:1 classid 1:900 htb rate 1mbit ceil ${toString lanRate}mbit
    $tc qdisc replace dev lan parent 1:250 cake dual-dsthost
    $tc qdisc replace dev lan parent 1:900 fq_codel
    $tc filter replace dev lan parent 1: protocol all prio 1 handle 250 fw classid 1:250
  '';

  downScript = pkgs.writeShellScript "etra-shaping-down" ''
    set -eu
    tc=${pkgs.iproute2}/bin/tc
    $tc qdisc del dev wan root 2>/dev/null || true
    $tc qdisc del dev lan root 2>/dev/null || true
    $tc qdisc del dev wan ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link del ifb4wan 2>/dev/null || true
  '';
in
{
  systemd.services.kdn-wan-shaping = {
    description = "Traffic shaping on etra: HTB and CAKE on wan and lan";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "systemd-networkd.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = upScript;
      ExecStop = downScript;
    };
  };
}
```

This is the shallow variant: no named-host classes yet, only the "others" class and a `cake` leaf.
Add the named classes from piece A and piece C when a real host needs a floor or a cap. The
`networking.nftables.tables.kdn-shaping` block shown above belongs in the same file or in the host
module; without it, every packet falls to the unmarked class.

Notes on the shape:

- Piece B is **not** in this module on purpose. Add it only when the `drek` measurement says the
  download must move here. It needs `${pkgs.kmod}/bin/modprobe ifb` and `cls_matchall`.
- `Type = "oneshot"` plus `RemainAfterExit = true` is the brys pattern. `ExecStop` is the rollback.
- `after = [ "systemd-networkd.service" ]` matters: `etra` builds `wan` and `lan` with
  `systemd-networkd` (measured: `systemctl is-active systemd-networkd` = active). A qdisc added
  before the bond exists is lost.
- A qdisc is **not** part of the networkd configuration. A `systemctl restart systemd-networkd`,
  a bond rebuild or a switch rebuild drops it. Re-run the unit. Do not add a timer; check
  `tc qdisc show dev wan` first in the measurement script.
- Do not use `networking.tc`: NixOS has no such option. `systemd.network` has
  `TrafficControlQueueingDiscipline`, but it only sets a simple root qdisc kind and cannot express
  an HTB tree with marks. A oneshot is the supported path.

## Rollback

Three levels, from softest to hardest.

```sh
# 1. stop the unit; ExecStop deletes every qdisc it added
sudo systemctl disable --now kdn-wan-shaping

# 2. remove the marks, so no packet carries a stale class
sudo nft delete table inet kdn-shaping     # returns on the next switch if it stays in config

# 3. manual, if the unit is already gone
sudo tc qdisc del dev wan root
sudo tc qdisc del dev lan root
sudo tc qdisc del dev wan ingress
sudo ip link del ifb4wan
```

The durable rollback is the configuration: remove the file from `imports` and run
`nixos-rebuild switch`. `nft delete table` alone is temporary because the NixOS ruleset is rebuilt
on every switch.

Keep the unit `disable`d until the measurement run is ready. `systemctl start` applies it,
`systemctl stop` removes it, and no reboot is needed.

## Measurement plan

Run from a LAN host (`oams`), not from `etra`, so the router's own CPU is not in the test path for
the far end.

| #   | Test                             | Command                                                                                | Pass                                     |
| --- | -------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------- |
| 1   | LAN link unchanged               | start `iperf3 -s` on `etra` for the test, then `iperf3 -c etra -t 30 -P 4` from `oams` | ≥ 900 Mbit/s (1 G port)                  |
| 2   | Tree does not throttle intra-LAN | `iperf3 -c <lan-host> -t 30` via `etra`                                                | within 2 % of the direct value           |
| 3   | Upload share per host            | two `iperf3 -c <public> -t 30` flows from two hosts                                    | each ≥ 50 % of an equal share            |
| 4   | Download share per host          | two parallel large downloads on two hosts                                              | each ≥ 50 % of an equal share            |
| 5   | Download cap works               | one host downloads, `tc -s class show dev lan`                                         | `1:201` rate matches the setting         |
| 6   | Inner queue is small             | `tc -s class show dev lan`                                                             | `1:10` backlog small while `drek` shapes |
| 7   | Latency under load               | `irtt client --hmac=irttuser -d 60s -i 100ms irtt.heistp.net`                          | added RTT ≤ 20 ms                        |
| 8   | No new loss                      | `nstat -az \| grep -E "TcpRetransSegs\|TcpExtTCPLostRetransmit"` before and after      | no step change beyond the baseline       |
| 9   | CPU headroom                     | `top -bn1 \| head -12` during tests 3 and 4                                            | one core not saturated                   |

Tools: `irtt` and `flent` are in nixpkgs (verified in the vendored tree). `iperf3` exists only in
the `kdn` user profile on `etra`, not system-wide. `etra` runs `kdn.minimalServer = true`, so run
the probes from `oams` and keep the router lean. `flent rrul` needs a `netserver` on the far side;
use the public `netperf-eu.bufferbloat.net` [S10], or accept `irtt` + `curl` as the pair.

Sampling during a test:

```sh
watch -n1 'tc -s class show dev wan | sed -n "1,25p"; tc -s class show dev lan | sed -n "1,25p"'
```

Read `backlog` and `dropped` per class. A class that shows a standing backlog while the total is
below its rate is misconfigured, not busy.

## Risks

- **Two shapers in series must run at equal rates.** If `etra`'s qdisc is faster than `drek`'s, it
  never drops and its fairness is inert. If it is much slower, `drek` stops mattering. Set them
  equal and check the inner `backlog`.
- **The `lan` root can throttle local traffic if it is mis-sized.** Root `4900mbit` and
  `1:900`'s `ceil 4900mbit` are what keep intra-LAN copies out of the policy. Test 2 catches a
  mistake here.
- **The `wan` bond has one active slave.** Its ceiling is 1 Gbit/s, so an upload setting near
  1 Gbit has no headroom to queue.
- **A qdisc on a bond dies with the bond.** Networkd rebuilds it. Re-run the unit.
- **No `cake_mq`.** One core per qdisc. Measure; the N6005 has 4 cores and plenty of headroom.
- **The nft marks are IPv4-only.** IPv6 falls to the catch-all classes. Acceptable for a policy
  layer, and the `cake` leaves still share fairly.
- **`etra` sees a 1 Gbit/s link to `drek`.** It cannot detect an ISP line slower than that. Its
  rates come from `drek`'s measurement, passed by hand.

## Sources

- **[S1]** `tc-cake(8)` — <https://man7.org/linux/man-pages/man8/tc-cake.8.html>
- **[S2]** `tc-htb(8)` — <https://man7.org/linux/man-pages/man8/tc-htb.8.html>
- **[S3]** `tc-flow(8)` — <https://man7.org/linux/man-pages/man8/tc-flow.8.html>
- **[S10]** Flent documentation — <https://flent.org/intro.html>
- **[S11]** IRTT README — <https://github.com/heistp/irtt>
- **[S18]** nftables wiki, "Netfilter hooks" — ingress acts before prerouting, conntrack at
  priority -200: <https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks>
- In-repo precedent: `hosts-den/brys/wan-shaping.nix` (oneshot with `ExecStart`/`ExecStop`).
- NixOS `networking.nftables.tables`, as already used by `modules/den/aspects/net-router/base.nix`.
