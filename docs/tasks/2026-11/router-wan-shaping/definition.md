---
type: Task
description: Design router-side traffic shaping so a single bulk client cannot starve the WAN — a CAKE layer on the drek border router and an internal layer on the etra NixOS router, with a shared rule for how the two compose.
status: open
authored_by: agent
timestamp: 2026-11-19T05:30:00+01:00
---

# Router-side shaping: make the WAN play nicely under load

Research only. This task changes no router. It fixes the design, the numbers and the
verification commands. Implementation is a later run, on each device, with the owner present.

## Context

The home network is a chain of three devices:

| Device | Role                  | WAN side                                            | LAN side                                              | Measured 2026-11-19                  |
| ------ | --------------------- | --------------------------------------------------- | ----------------------------------------------------- | ------------------------------------ |
| `drek` | OpenWrt border router | 1 Gbit/s port to the ISP, `94.240.3.230/30`         | 1 Gbit/s port to `etra`                               | `wan` and `lan3`/`lan4` at 1000 Mb/s |
| `etra` | NixOS internal router | bond `wan`, active-backup, one slave `enp1s0`       | bond `lan`, LACP, `enp2s0` + `enp3s0`                 | `enp1s0` 1000 Mb/s full duplex       |
| `etra` | NixOS internal router | `192.168.40.1/31` peer `192.168.40.0` toward `drek` | `192.168.73.1/24`, `192.168.252.1/24`, `10.92.0.1/24` | `ip -br addr`                        |

The chain is `client → etra → drek → ISP`. `etra`'s `wan` bond has one member, so the link between
the two routers is 1 Gbit/s in each direction.

Both routers carry **no shaping today**: `tc qdisc show dev wan` returns `noqueue` on `drek`
and on `etra`. The only rate limit in the fleet is host-side: `hosts-den/brys/wan-shaping.nix`
caps inbound TCP/443 at 600 Mbit/s on `brys` itself.

The symptom: one bulk client fills the 1 Gbit/s line, and every other flow then sees stalled
handshakes and high latency until the transfer ends. Measured on `brys` on 2026-11-18: an
unconstrained Hugging Face download reached **105 MB/s**, recorded as 845 Mbit/s in the host
README, and other hosts could not complete a TCP handshake during it.

## What "play nicely" means

Three targets. Each one is a number you can measure.

| #   | Target              | Number                                                                      | How it is measured                                                          |
| --- | ------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1   | Latency under load  | added RTT **≤ 20 ms** over idle, in both directions                         | `irtt` or `flent` from a LAN client to a public server, idle then saturated |
| 2   | Per-client fairness | a competing host gets **≥ 50 %** of an equal share while the bulk host runs | two parallel bulk flows from two LAN hosts, rates from `tc -s`              |
| 3   | A bulk class        | bulk traffic fills all spare capacity, and gives way within one RTT         | `tc -s qdisc` tin counters, plus target 1 while bulk runs                   |

Target 1 follows the bufferbloat project: "If the test shows latency below 15-25 msec, it means
that bufferbloat is under control" [S6]. The idle baseline on `drek` is small: `ping 1.1.1.1`
from the router measured **0.933 ms** round-trip [M14]. So any loaded RTT above ~20 ms is queue,
not distance.

The owner reports that game traffic stays usable today only when nothing else runs. That is the
behaviour these three numbers must fix.

## The classic result: Tomato on a 1 Mbit/s / 256 kbit/s line

The owner cites a Tomato router on a 1 Mbit/s down, 256 kbit/s up line. Games stayed responsive
while torrents ran flat out. This is the reference case, and it explains why a small rate limit
works better than a big one.

### Why it worked

1. **The line was the problem, not the router.** At 1 Mbit/s, one second of data is 125 kB. A
   modem buffer of 256 kB therefore holds 2 s of standing delay. Any bulk flow fills that buffer
   and every other packet waits behind it.
2. **Tomato moved the bottleneck into the router.** The QoS page sets an outbound and inbound
   rate below the measured line speed. FreshTomato's own procedure averages three speed tests at
   different hours and takes **85 %** of that average [S17]. The router's queue discipline is now
   the slowest point, so the queue lives where it can be bounded and scheduled. The ISP buffer
   stays empty.
3. **Classes turned "first come" into "who matters".** Traffic goes into priority classes. A
   game's small UDP flow sits in the top class; torrents sit in a low class. Tomato builds these
   classes with HTB, where `rate` is the bandwidth a class is **guaranteed** and `ceil` is the
   maximum it may take "if its parent has bandwidth to spare" [S2]. The guarantee is the part
   that keeps the game alive when the line is full. The torrent still uses every bit the top
   class does not want.
4. **A fair-queuing leaf stopped one client owning a class.** Inside each class Tomato uses WFQ.
   The FreshTomato wiki states the order: "Packets in the Priority class always come first. If
   Priority is empty, WFQ is applied among all other classes" [S9]. One torrent client with 300
   connections therefore shared its class with the others, instead of taking it.
5. **The cap was low enough to stay honest.** On a 1 Mbit/s line, a 10 % derate is 100 kbit/s —
   more than the whole game flow needs. The cost of the reservation was invisible. On a
   1 Gbit/s line the same 10 % is 100 Mbit/s, so the derate costs more and the sizing matters.

### What it did not have

Tomato had **no active queue management**. Its class queues are plain FIFO unless a fair-queuing
leaf is added, and SFQ/WFQ has no delay-based drop rule. Latency stayed low because the reserved
class was small and the total queue was short — not because the queue was actively managed. This
is the one place where CAKE is a different tool, not a faster Tomato.

## Mapping onto CAKE and SQM

| Tomato part                               | CAKE part                                                                                                                                                                                                                                                               | Source    |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Outbound/inbound rate at 85-90 % of line  | `bandwidth RATE`. CAKE uses a **deficit-mode** shaper, so it needs no bucket size and "can therefore be set much closer to the actual link speed" than a TBF                                                                                                            | [S1] [S7] |
| Priority classes                          | `diffserv3` / `diffserv4` tins. `diffserv3` is Bulk / Best Effort / Voice; CS1 and LE map to Bulk                                                                                                                                                                       | [S1]      |
| A guarantee that games always get through | Tin thresholds plus **soft admission control**: a class over its threshold is demoted, never starved. "If there is no competing traffic, any traffic class can use the full link bandwidth, but it is always possible for new traffic in a different class to start up" | [S7]      |
| WFQ leaf                                  | DRR++ over per-flow queues. Sparse flows are served first — the design assumption is that latency-sensitive traffic is sparse                                                                                                                                           | [S7]      |
| The missing AQM                           | COBALT (CoDel + BLUE) per queue, `target` 5 ms and `interval` 100 ms at our rates                                                                                                                                                                                       | [S1] [S7] |
| Per-client fairness (only partly present) | `triple-isolate` (default), or `dual-srchost` / `dual-dsthost` for strict per-host order, plus `nat` to see through NAT                                                                                                                                                 | [S1]      |

Two differences matter for this task:

- **CAKE's own classifier reads DSCP, not a rule table.** A bulk class therefore needs a mark. The
  man page offers two overrides when DSCP is not enough: `fwmark` for the tin, and `tc` filters
  that set `skbedit priority` [S1]. Without either, the options are a host that sets CS1, or no
  mark at all plus per-host fairness. SQM also adds `wash` on ingress by default (`squash_dscp`
  defaults to 1), which **erases** inbound DSCP marks [M10]. So an inbound bulk class built from
  DSCP does not survive SQM. Design the download bulk policy with per-host fairness, not with
  marks (see [drek.md](drek.md)).
- **CAKE costs CPU.** It is a single-queue qdisc with a global lock, so one core carries the whole
  shaped rate [S1]. On a Cortex-A53 that ceiling is low (see [drek.md](drek.md)).
- **The ISP-scale tool does not fit here.** LibreQoS is the reference implementation of
  per-subscriber CAKE + HTB. Its own sizing guide asks for 2 or more strong cores, a 10G-class NIC
  and 8 GB of RAM before it carries ~1 000 subscribers [S8]. The border router has 489 MiB. The
  design must be two small `tc` setups, not a QoE middlebox.

## The two-layer plan

### Layer A — `drek`, at the border

`drek` is the only device that sees the real ISP rate. It owns the aggregate shaper.

- **Download:** an `ifb` device (`ifb4wan` if SQM is used) receives redirected ingress, and CAKE
  runs there in `ingress` mode.
- **Upload:** CAKE on `wan` egress.
- **Fairness here is coarse.** `drek` masquerades for the house (`firewall.wan.masq='1'` [M7]), and
  `etra` masquerades again toward `drek` (`IPMasquerade = "ipv4"` in `modules/den/aspects/net-router/base.nix`).
  So every home packet reaches `drek`'s conntrack as `192.168.40.1`. CAKE `nat` can separate
  `etra`'s aggregate from `drek`'s own clients and `wg0`, but it **cannot** separate `brys` from
  `oams`. Do not expect it to.
- **Ceiling:** whatever CAKE can actually hold on a 1.35 GHz dual-core A53. The measured
  reference is ~420 Mbit/s on this exact SoC [S5].

### Layer B — `etra`, on the internal side

`etra` does not know the ISP rate. It sees a 1 Gbit/s point-to-point link to `drek`. It owns
**fairness and policy**, and it is the only device that can: it sees the real host addresses in
both directions.

- **Upload:** an HTB tree on `wan` egress, keyed by source marks. LAN→WAN packets never leave by
  `lan`, so this is the only place an upload tree can live.
- **Download:** an HTB tree on `lan` egress, keyed by destination marks. The packet is already
  DNATed there, so `ip daddr` is the real host. An `ifb` on `wan` ingress is added only for the
  aggregate when `drek` cannot hold the rate; `tc` ingress runs before prerouting, so per-host
  policy does not work there [S18].
- **Host policy:** a reserved class for interactive hosts, a bulk cap for the one or two hosts
  that cause the problem (today `brys`), and a fair default for everything else.

### How the layers compose

Six rules. The first three are the ones that go wrong.

1. **One device sets the aggregate rate.** `drek` owns it, because it can measure it.
2. **A second shaper on the same direction must run at 95-100 % of the outer rate.** Higher, and it
   never drops, so its fairness logic is inert. Much lower, and it is the only bottleneck while
   `drek` idles. "At or above" is wrong here: equal is the target.
3. **Per-host fairness lives on `etra`, in the direction that can see the host.** Upload on `wan`
   egress, download on `lan` egress. Neither `drek` nor an `ifb` on the WAN ingress can name a
   home host: the first sees `etra`'s address after one NAT, the second sees the public address
   before DNAT.
4. **Hard policy lives on `etra` as well.** A floor, a cap and the reserved class need a per-host
   mark, and only `etra` can key on a home address.
5. **Shaping the same direction twice is allowed only when the inner qdisc does not queue.** Check
   with `tc -s`: the inner qdisc must show a small `backlog` and near-zero drops. A standing
   backlog means it is the bottleneck. Move its rate up.
6. **Drop the reservation depth when `drek` shapes.** CAKE's tins already reserve. While `drek`
   runs a working shaper, `etra` needs only fair shares per host: one class per host at an equal
   rate, no reserved interactive class. Keep the deep reservation tree only while `drek` is
   unshaped or untrusted. This is the "drop the reservation depth" rule of the owner.

`etra`'s own traffic (containers, LiteLLM, Prometheus, build farm) leaves by `wan` directly and
never crosses `lan`. So the `lan` tree does not cover it. The upload tree on `wan` does, because
every packet on `wan` is WAN-bound.

## Measured state (2026-11-19)

Facts that the design depends on. Each one is a read-only command against the live device. The
`[M…]` references in this file and in [drek.md](drek.md) point at this table.

| #   | Fact                   | Device | Value                                                                                                                                                                                            | Command                                                            |
| --- | ---------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------ |
| M1  | Model, release, kernel | `drek` | Linksys E8450 (UBI), `mediatek/mt7622`, OpenWrt 24.10.5, kernel 6.6.119                                                                                                                          | `cat /tmp/sysinfo/model`, `/etc/openwrt_release`                   |
| M2  | CPU                    | `drek` | **2** cores, Cortex-A53, max 1.35 GHz, governor `ondemand`                                                                                                                                       | `grep -c ^processor /proc/cpuinfo`                                 |
| M3  | Tools                  | `drek` | `tc` 6.11 as `tc-tiny`; `tcpdump` yes; `ethtool`, `nstat`, `irtt`, `flent`, `iperf3` no; `opkg` carries none of them                                                                             | `ls -l /sbin/tc`, `command -v`, `opkg list`                        |
| M4  | RAM                    | `drek` | 500 492 kB total, ~377 MB available                                                                                                                                                              | `free -m`                                                          |
| M5  | SQM instance           | `drek` | one, interface **`eth1`**, `enabled=0`, 85 000/10 000 kbit, `piece_of_cake.qos`                                                                                                                  | `uci show sqm`                                                     |
| M6  | `eth1` exists?         | `drek` | **no** — only `eth0`, `lan1-4`, `wan`                                                                                                                                                            | `ls /sys/class/net`                                                |
| M7  | Firewall and WAN       | `drek` | `flow_offloading=1`, **`flow_offloading_hw=1`**, `wan.masq=1`; `wan` holds `94.240.3.230/30`, gw `94.240.3.229`                                                                                  | `uci show firewall`, `ip route`                                    |
| M8  | Qdiscs and links       | `drek` | `noqueue` on `wan`, `br-etra`, `br-lan*`; `mq` + `fq_codel` on `eth0`; `wan` 1000 Mb/s, `lan3`/`lan4` 1000 Mb/s, `lan1`/`lan2` no link                                                           | `tc qdisc show`, `/sys/class/net/*/speed`                          |
| M9  | `ifb` works            | `drek` | module loads; a probe `ifb` device was created and deleted on 2026-11-19                                                                                                                         | `ip link add probe-ifb type ifb`                                   |
| M10 | SQM script behaviour   | `drek` | `piece_of_cake` = `besteffort` both ways; `layer_cake` = `diffserv3`, adds `wash` on ingress (`squash_dscp` default 1); ifb named `ifb4<if>`; redirect is `u32 … mirred`; no `cake_mq` reference | `sed -n 1,60p /usr/lib/sqm/*.qos`, `grep -rn cake_mq /usr/lib/sqm` |
| M11 | Stuck mount            | `drek` | `/etc/config/fstab` mounts UUID `3e204e50-…` at `/mnt/diablo`; nothing mounted                                                                                                                   | `cat /etc/config/fstab`, `cat /proc/mounts`                        |
| M12 | Clock skew             | `drek` | epoch `1791715078` vs `1795062406` on `etra` → **3 347 328 s (38.7 days)** behind                                                                                                                | `date -u +%s` on both                                              |
| M13 | Hardware and modules   | `etra` | Pentium Silver N6005, 4 threads, 31.8 GB RAM, kernel 6.18.45; `tc` 7.2.0; `sch_cake`, `sch_htb`, `ifb`, `act_mirred`, `cls_matchall`, `cls_flow` present; `cake_mq` absent from the module       | `lscpu`, `free -m`, `tc -V`, `modinfo`                             |
| M14 | Idle RTT               | `drek` | **0.933 ms** to `1.1.1.1`                                                                                                                                                                        | `ping -c1 1.1.1.1`                                                 |
| M15 | Line rate, lower bound | fleet  | **845 Mbit/s** single stream, measured 2026-11-18                                                                                                                                                | `hosts-den/brys/README.md`                                         |
| M16 | Noise baseline         | `etra` | `TcpRetransSegs` 63 500, `TCPLostRetransmit` 16 610 over 85 days                                                                                                                                 | `nstat -az`                                                        |

Two claims in the task brief do not match the device. Both are recorded as measured, not as
assumed:

- `drek` is a **dual-core** A53 (MT7622BV), not quad. `grep -c ^processor /proc/cpuinfo` = 2, and
  the SoC is documented as dual-core in the E8450 report that measured it [S5].
- `drek` has **489 MiB** of RAM (500 492 kB), not 512 MB of usable memory. About 377 MB is free.

## Ranked implementation order

Ordered by value per unit of risk. Each step has a check that can fail.

| #   | Step                                                                                                                    | Device     | Why here                                                                                       | Check                                                                                                                                                            |
| --- | ----------------------------------------------------------------------------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Record the baseline: line rate, idle RTT, loaded RTT down and up, bulk share of two hosts                               | LAN client | No number exists today. Without it, no later change can be judged                              | Turn off all shaping, run the three targets; store the four numbers                                                                                              |
| 2   | Turn off **hardware** flow offload; prove a qdisc can hold a rate at all                                                | `drek`     | Hardware offload bypasses the qdisc — the probable cause of "200 Mbit set, 446 Mbit delivered" | `tc qdisc replace dev wan root tbf rate 300mbit burst 4mbit latency 40ms`, then a 30 s transfer: port counter and qdisc counter must agree within 5 %. Roll back |
| 3   | SQM `piece_of_cake.qos` on `wan`, one tin, at a rate CAKE can hold (~400 Mbit down, measured up)                        | `drek`     | Lowest-risk CAKE. One tin already gives AQM and per-flow fairness                              | Target 1 down and up at ≤ 20 ms, throughput at ≥ 90 % of the setting                                                                                             |
| 4   | HTB tree on `etra` `wan` egress, keyed by source marks, with a `cake` leaf; rate equal to `drek`'s upload               | `etra`     | The only place an upload can be shaped. Equal rate (rule 2)                                    | Target 2, upload direction                                                                                                                                       |
| 5   | HTB tree on `etra` `lan` egress, keyed by destination marks, `cake dual-dsthost` leaf, parent at `drek`'s download rate | `etra`     | The only place a home host can be named in the download                                        | Target 2, download direction                                                                                                                                     |
| 6   | Switch `drek` to `layer_cake.qos` and add the bulk policy (per-host ceiling, or CS1 + `diffserv3` on egress only)       | `drek`     | Adds the bulk class. Marks fail on ingress because SQM washes DSCP                             | Target 3, plus target 1 unchanged                                                                                                                                |
| 7   | Named-host classes and the reserved `prio 1` class on `etra` (deep mode)                                                | `etra`     | Reserved interactive capacity, plus a hard cap on the bulk host                                | Each host's rate matches its class; intra-LAN throughput unchanged                                                                                               |
| 8   | Re-run all three targets with both layers live, and record the numbers in this directory                                | both       | The proof                                                                                      | A table of before/after in a `done.md`                                                                                                                           |

Do not start at step 5. The bulk class is the least valuable step and the easiest to get wrong.

## Acceptance test

Run from one LAN client, with one bulk partner and one probe. Exact commands are in
[drek.md](drek.md#verification-without-the-dsa-counters) and [etra.md](etra.md#measurement-plan).

1. **Idle:** `irtt client -d 30s -i 100ms <public-server>` → mean and p95 RTT.
2. **Loaded down:** start a bulk download on host A, repeat step 1 → added RTT ≤ 20 ms.
3. **Loaded up:** same, upload direction.
4. **Fairness:** start an equal bulk flow on host B. Each host must get ≥ 50 % of an equal share
   within 10 s.
5. **Bulk class:** while host A runs bulk, start an interactive flow. Its RTT must stay within the
   step-1 band.

Store the five results, dated, in this directory. A change that does not move at least one of
them is not a fix.

## Pre-existing defects (record, do not fix here)

Both are outside this task. They will affect the work, so they are written down.

1. **`drek` clock is 38.7 days behind.** Measured 2026-11-19: `drek` reports epoch `1791715078`
   (`Sun Oct 11 12:37 CEST 2026`), `etra` reports `1795062406` (`Thu 19 Nov 05:26 CET 2026`). The
   difference is 3 347 328 s. Consequence: timestamps in `tc -s` logs, `flent` runs and any
   signed or certificate-based test are wrong by 38 days. Compare durations, never wall-clock
   times, until it is fixed.
2. **`drek` boot waits on a missing `/mnt/diablo`.** `/etc/config/fstab` holds a mount entry for
   UUID `3e204e50-94ab-4e4a-89f6-0528836c03c0` with `enabled '1'`. Nothing is mounted: `/proc/mounts`
   has only `/overlay`. With `delay_root 5` and `check_fs 1`, the boot path retries the mount.
   Consequence: a reboot during implementation takes longer than expected. Do not remove the entry
   in this task.

## Sub-tasks

This task keeps two per-layer design notes and no sub-task directory. Each one is a design note
with a back-link here.

- [drek.md](drek.md) — the OpenWrt side: SQM and CAKE, the ingress `ifb`, the correct
  `download`/`upload` values, the Cortex-A53 budget, the DSA counter problem, and the per-host
  fairness recipe.
- [etra.md](etra.md) — the NixOS side: a declarative `tc` setup, an upload tree on `wan` and a
  per-host download tree on `lan`, the optional `ifb` aggregate, the NixOS service shape, the
  rollback path and the measurement plan.

## Sources

The numbering is shared by all three files. A note cites the subset it uses.

- **[S1]** `tc-cake(8)`, iproute2, read 2026-11-19 — <https://man7.org/linux/man-pages/man8/tc-cake.8.html>
- **[S2]** `tc-htb(8)`, iproute2, read 2026-11-19 — <https://man7.org/linux/man-pages/man8/tc-htb.8.html>
- **[S3]** `tc-flow(8)`, iproute2, read 2026-11-19 — <https://man7.org/linux/man-pages/man8/tc-flow.8.html>
- **[S4]** `sqm-scripts` README (tohojo), read 2026-11-19 — <https://github.com/tohojo/sqm-scripts>
- **[S5]** `sqm-scripts` issue #142, "Please allow setting different QDISC in Ingress and Egress",
  opened 2021-12-05, read 2026-11-19 — <https://github.com/tohojo/sqm-scripts/issues/142>
- **[S6]** Bufferbloat project, "What Can I Do About Bufferbloat?", updated 2026-02-16, read
  2026-11-19 — <https://www.bufferbloat.net/projects/bloat/wiki/What_can_I_do_about_Bufferbloat/>
- **[S7]** Bufferbloat project, "Cake Technical Information", read 2026-11-19 —
  <https://www.bufferbloat.net/projects/codel/wiki/CakeTechnical/>
- **[S8]** LibreQoS, "System Requirements" (v2.0), read 2026-11-19 —
  <https://libreqos.readthedocs.io/en/latest/docs/v2.0/requirements.html>
- **[S9]** FreshTomato wiki, "QoS settings", last modified 2025-09-13, read 2026-11-19 —
  <https://wiki.freshtomato.org/doku.php/qos-settings>
- **[S10]** Flent documentation, "Introduction", read 2026-11-19 — <https://flent.org/intro.html>
- **[S11]** IRTT README, read 2026-11-19 — <https://github.com/heistp/irtt>
- **[S12]** OpenWrt wiki, "SQM (Smart Queue Management)". The page is behind a bot check; the
  relevant sentences were read from the search-result excerpt on 2026-11-19 —
  <https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm>
- **[S13]** OpenWrt forum, "Belkin RT3200/Linksys E8450 WiFi AX discussion" (page 68: "I cap out at
  600-700 MBit") and Reddit r/openwrt "RT3200/E8450 low SQM CAKE Performance" ("~390 mbps
  throughput. Htop shows one core being pegged at 100 %"). Forum reports, read as excerpts
  2026-11-19. Treated as a range, not as a measurement.
- **[S14]** OpenWrt device page, "Linksys E8450 (aka. Belkin RT3200)" — minimum CPU frequency tip
  (600 MHz). Read as an excerpt 2026-11-19.
- **[S15]** Köppeler et al., "Have your CAKE and eat it too: Scaling software rate limiting across
  CPU cores", IEEE LANMAN 2025, cited by `tc-cake(8)` [S1] for the `cake_mq` shared-shaper
  algorithm. Not read: the PDF was fetched and could not be parsed.
- **[S16]** Facts labelled `[M1]`…`[M16]` were taken read-only on 2026-11-19 with `ssh drek` and
  `ssh etra`. The table is in the "Measured state" section above. One exception to read-only: the
  `ifb` probe in `[M9]` created and immediately deleted a spare `ifb` device to prove that the
  module loads.
- **[S17]** FreshTomato wiki, "Bandwidth Limiter", last modified 2025-11-15, read 2026-11-19 — the
  85 % rule and the three-test averaging procedure: <https://wiki.freshtomato.org/doku.php/bwlimit>
- **[S18]** nftables wiki, "Netfilter hooks", last edited 2023-12-22, read 2026-11-19 — the ingress
  hook and `tc` ingress "take effect even before prerouting"; connection tracking sits at priority
  -200 and destination NAT at -100: <https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks>
