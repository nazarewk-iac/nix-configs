---
type: Design
description: OpenWrt side of the router shaping plan — SQM and CAKE on drek, ingress by ifb, the correct download/upload values for the ISP line, the Cortex-A53 CPU budget, the DSA counter problem and the per-host fairness recipe.
status: open
task: definition.md
authored_by: agent
timestamp: 2026-11-19T05:35:00+01:00
---

# `drek` — CAKE at the border

`drek` is the Linksys E8450 that sits at the ISP edge. It is the only device that sees the real
line rate, so it owns the aggregate shaper. This note fixes what to run there, what numbers to
use, and how to prove it works when the port counters lie.

Read the umbrella first: [definition.md](definition.md).

## Facts measured on the device (2026-11-19)

| Item            | Value                                                                       | Command                                 |
| --------------- | --------------------------------------------------------------------------- | --------------------------------------- |
| Board           | Linksys E8450 (UBI), `mediatek/mt7622`                                      | `cat /tmp/sysinfo/model`                |
| Release         | OpenWrt 24.10.5 `r29087-d9c5716d1d`                                         | `cat /etc/openwrt_release`              |
| Kernel          | 6.6.119                                                                     | `uname -r`                              |
| CPU             | Cortex-A53, **2** cores, max 1.35 GHz, `ondemand`                           | `grep -c ^processor /proc/cpuinfo`      |
| RAM             | 500 492 kB total, ~377 MB available                                         | `free -m`                               |
| Shaper packages | `sqm-scripts` 1.6.0, `kmod-sched-cake` 6.6.119-r1, `luci-app-sqm`           | `opkg list-installed`                   |
| `tc`            | `/sbin/tc -> /usr/libexec/tc-tiny`, iproute2 6.11.0                         | `ls -l /sbin/tc`, `tc -V`               |
| SQM instance    | `eth1`, **disabled**, `download 85000`, `upload 10000`, `piece_of_cake.qos` | `uci show sqm`                          |
| Netdevs         | `eth0`, `lan1`…`lan4`, `wan`, bridges, `wg0`, `wl0-ap*`. **No `eth1`**      | `ls /sys/class/net`                     |
| `wan` speed     | 1000 Mb/s                                                                   | `cat /sys/class/net/wan/speed`          |
| `wan` kind      | DSA user port under `1b100000.ethernet`                                     | `readlink -f /sys/class/net/wan/device` |
| Offload         | `flow_offloading=1`, `flow_offloading_hw=1`                                 | `uci show firewall`                     |
| NAT             | `firewall.wan.masq=1`                                                       | `uci show firewall`                     |
| Idle RTT        | 0.933 ms to `1.1.1.1`                                                       | `ping -c1 1.1.1.1`                      |
| Missing tools   | no `ethtool`, `nstat`, `irtt`, `flent`, `iperf3`; `tcpdump` present         | `command -v`                            |
| SQM init script | enabled at boot, but its one instance is disabled                           | `/etc/init.d/sqm enabled`               |

Two of these decide the whole design:

1. The SQM instance names `eth1`. That device does not exist on this DSA build. The instance is
   also `enabled=0`, so **SQM itself shaped nothing on 2026-11-18**. If that run used raw `tc`
   instead, this cause does not apply and the next one becomes the main suspect.
2. Hardware flow offload is on. OpenWrt documents SQM as incompatible with it [S12].

## How SQM builds the shaper

`sqm-scripts` writes one `tc` command per direction [S4]:

- **Egress.** `tc qdisc add dev $IFACE root cake bandwidth ${UPLINK}kbit …`
- **Ingress.** It creates an `ifb` device named `ifb4$IFACE` (so `ifb4wan` for `wan`), adds an
  ingress qdisc to `$IFACE`, and redirects packets to the `ifb`. CAKE is attached to the `ifb`
  root with `bandwidth ${DOWNLINK}kbit` [S4]. Read on the device: the redirect rule is
  `u32 match u32 0 0 … action mirred egress redirect dev $DEV`.

The two scripts differ in the tin layout, not in the shaper:

| Script              | Cake options used                                                                                   | Tins                               |
| ------------------- | --------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `piece_of_cake.qos` | `besteffort` for both directions (it ignores the `*_CAKE_OPTS` defaults)                            | one                                |
| `layer_cake.qos`    | `diffserv3` by default; adds `besteffort` when `squash_ingress=1`, adds `wash` when `squash_dscp=1` | three (Bulk / Best Effort / Voice) |

Both behaviours were read in `/usr/lib/sqm/piece_of_cake.qos` and `/usr/lib/sqm/layer_cake.qos`
on 2026-11-19. `defaults.sh` sets `ZERO_DSCP` and `IGNORE_DSCP` to 1, so **`wash` is on by
default for the download direction**. That erases inbound DSCP marks, which is why an inbound
bulk class cannot be built from marks (see "Per-host fairness" below).

Units: `download` and `upload` are **kbit/s**, not Mbit/s. `85000` is 85 Mbit/s. The old instance
was sized for a VDSL-era line and is wrong for this one.

## Ingress shaping with `ifb`

A qdisc only sees traffic that leaves an interface. Download traffic arrives on `wan`, so SQM
copies it to `ifb4wan` and shapes it there. The cost is one extra device pass per packet, and one
more copy on a CPU that has no cycles to spare.

The `ifb` path works on this device: the module loads, and a probe `ifb` device was created and
deleted on 2026-11-19 [M9].

Two keywords belong on the ingress CAKE:

- `ingress` — "changes the shaper to also count dropped packets as data transferred, as these will
  have already traversed the link" [S1]. On the download side this is the correct accounting.
- `nat` — needed because `drek` masquerades for the whole house; without it CAKE sees one internal
  address (the NAT source), not the real hosts [S1].

`sqm-scripts` 1.6.0 adds neither by default. Pass them through `iqdisc_opts`.

## Correct `download` and `upload` values

A 1 Gbit/s port is not a 1 Gbit/s line. Measure first. The procedure, in order:

1. **Stop all shaping.** `uci set sqm.<if>.enabled='0'; uci commit sqm; /etc/init.d/sqm stop`.
2. **Measure the peak.** From a wired LAN host, run four parallel TCP streams to a fast public
   endpoint for 30 s, three times, at different hours. Record the highest 10 s average.
   A single stream measures the CDN, four streams measure the line.
3. **Derate.** The bufferbloat project says to set the shaper at the measured value and then
   reduce until latency stays low [S6]. FreshTomato's classic rule is **85 % of a three-test
   average** [S17]. CAKE's deficit shaper can sit closer to the line than a TBF [S1], so use
   **90-95 % of the four-stream peak**.
4. **Clamp to the CPU ceiling** (next section). The lower of the two numbers is the setting.

Known numbers:

- The line carries **at least 845 Mbit/s**: `brys` measured 105 MB/s on an unconstrained download
  on 2026-11-18 (`hosts-den/brys/README.md`). That number came from one stream.
- The stale config had `download 85000` / `upload 10000`. Those are 85/10 Mbit/s. They belong to a
  previous line and must not be reused.

Worked rule:

```
download = min(0.90 * measured_down_kbit, cake_ceiling_kbit)
upload   = min(0.90 * measured_up_kbit,   cake_ceiling_kbit)
```

If `0.90 * measured_down` is larger than the CPU ceiling, you cannot shape the download here.
Go to "Option S" below.

## CPU budget on a Cortex-A53

CAKE is a single-queue qdisc with a global lock: "it does not scale across multiple CPUs. This
limits the maximum bandwidth the shaper can handle to that achievable on a single CPU" [S1]. The
second A53 core does not help.

Published and reported ceilings for this exact SoC:

| Source                  | Configuration                                                                   | Result                                              |
| ----------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------- |
| `sqm-scripts` #142 [S5] | E8450/RT3200, MT7622BV 1.35 GHz, `cake` + `layer_cake.qos`, 600 000/20 000 kbit | **~420 Mbit/s** download, one core saturated        |
| Reddit r/openwrt [S13]  | same board, `cake` SQM, 520 Mbit setting                                        | **~390 Mbit/s**, "one core being pegged at 100 %"   |
| OpenWrt forum [S13]     | same board                                                                      | "I cap out at 600-700 MBit" — best case, unverified |
| Ten64 forum [S13]       | generic Cortex-A53                                                              | "cake will run out of a53 cpu at about 500Mbit"     |

Take **400-450 Mbit/s** as the working ceiling for a shaped direction. The download direction pays
one extra pass through the `ifb`, so its ceiling is the lower of the two. Prove it on this device
with a ramp test; do not trust a number from another board: the governor is `ondemand`, the clock
drops, and thermal state matters.

Two facts make the ceiling worse than the table suggests:

- The governor is `ondemand`, and the OpenWrt device page recommends raising the minimum frequency
  to 600 MHz for stability [S14]. During measurement, pin it: `echo performance >
/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`. That is a temporary change, and it is
  part of the measurement, not of the shipped config.
- `cake_mq`, the multi-queue CAKE variant that scales across cores, is not available here. `tc`
  parses it, but `sqm-scripts` 1.6.0 has no reference to it (grep over `/usr/lib/sqm` found none),
  and the shipped kernel is 6.6. `cake_mq` is the 2025 answer to this exact problem [S15]; it is
  not usable on this image today.

### Option S — split the directions

If the line is really ~940 Mbit/s, then 420 Mbit/s of CAKE costs more than half the line. In that
case:

- **`drek` shapes the upload only.** The ISP upload is usually far below 1 Gbit/s, so one A53 core
  can hold it. This is the cheap, near-edge direction.
- **`etra` shapes the download**, on x86, at the line rate, with the tree on `lan` egress (piece C
  in [etra.md](etra.md)). It sits one routed hop further from the ISP.

Decide with the measurement: if `0.90 * measured_down` exceeds the CAKE ceiling on this board
(~450 000 kbit/s), take Option S. If the line measures below that, keep both directions on `drek`
— it is simpler and closer to the edge.

## The DSA counter problem

The observed defect: a 200 Mbit CAKE setting delivered **446 Mbit/s** on 2026-11-18, and the DSA
port counters did not show the shaped rate (`hosts-den/brys/wan-shaping.nix`).

On this device `wan` is a DSA user port. Its statistics come from the switch/DSA layer, not from
the qdisc. `eth0` is the DSA master. That explains "the counters do not show shaping", but it
does **not** explain 446 Mbit/s from a 200 Mbit setting. Three candidate causes exist, and two of
them are visible on the device today:

| #   | Candidate                                                      | Evidence                                                                                                                            | Test that separates it                                                        |
| --- | -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 1   | Hardware flow offload bypasses the qdisc                       | `flow_offloading_hw='1'` [M7]. OpenWrt: SQM is "incompatible with hardware flow offloading which bypasses part of the kernel" [S12] | Turn it off, repeat the 300 Mbit `tbf` test. Rate must hold                   |
| 2   | SQM ran on a device that carries no traffic                    | instance names `eth1`, which does not exist; `enabled=0` [M5][M6]                                                                   | `tc -s qdisc show dev wan` and `dev ifb4wan` must show `Sent` bytes that grow |
| 3   | The shaper was attached to `br-lan` or `eth0` instead of `wan` | Not confirmable after the fact                                                                                                      | `tc qdisc show` must list the qdisc on `wan` and on `ifb4wan` only            |

The right conclusion is not "CAKE does not work here". It is "the 2026-11-18 run probably did not
shape, and the counters cannot be the oracle". Fix the oracle first.

### The differential counter test

This is the test that distinguishes "not shaped" from "counter is wrong". Run it for 30 s during
a bulk **upload**:

```sh
# on drek, before
tc -s qdisc show dev wan | sed -n '1,3p'
cat /sys/class/net/wan/statistics/tx_bytes
sleep 30
tc -s qdisc show dev wan | sed -n '1,3p'
cat /sys/class/net/wan/statistics/tx_bytes
```

For a bulk **download**, run the same pair of reads on `ifb4wan`, and compare its `Sent` delta with
`cat /sys/class/net/wan/statistics/rx_bytes`. The `ifb` is where the download qdisc sits.

Read the result like this:

| qdisc `Sent` delta | port `tx_bytes` delta | Meaning                                     |
| ------------------ | --------------------- | ------------------------------------------- |
| ≈ shaped rate      | ≈ shaped rate         | shaping works, the counters agree           |
| ≈ shaped rate      | ≫ shaped rate         | **offload bypass**: traffic skips the qdisc |
| 0                  | ≫ 0                   | the qdisc is not on the path at all         |

The qdisc counter is the shaped number. The port counter is only a bypass detector.

## Verification without the DSA counters

Five checks. Use all of them; none is sufficient alone.

1. **The qdisc's own counters** — the shaped rate, the drops, the delay.
   ```sh
   tc -s qdisc show dev wan
   tc -s qdisc show dev ifb4wan
   tc -s class show dev wan
   ```
   In the `cake` block, read `Sent bytes`, `dropped`, `overlimits`, `backlog`, and per tin
   `pk_delay` / `av_delay`. The AQM `target` is 5 ms at our rates [S1], so a sustained `av_delay`
   above ~10 ms means the queue is building.
2. **End-to-end throughput**, which is the truth the user feels. From a LAN host:
   ```sh
   curl -o /dev/null -w '%{speed_download}\n' https://<fast-mirror>/<large-file>
   ```
   Compare with the setting. 90-95 % is correct; 100 % or more means no shaping.
3. **TCP counters on the neighbour.** `drek` has no `nstat`. `etra` does. A shaper that drops
   aggressively raises retransmits there:
   ```sh
   ssh etra 'nstat -az | grep -E "TcpRetransSegs|TcpExtTCPLostRetransmit"'
   ```
   Baseline measured 2026-11-19: `TcpRetransSegs` 63 500 and `TcpExtTCPLostRetransmit` 16 610
   over 85 days of uptime. Treat a large step change as a signal, not as an absolute.
4. **Latency probe under load.** `drek` has neither `irtt` nor `flent` and `opkg` has no such
   package [M3]. Run the probe from a LAN host instead:
   ```sh
   irtt client --hmac=irttuser -d 60s -i 100ms irtt.heistp.net   # public test server [S11]
   flent rrul -p all_scaled -l 60 -H netperf-eu.bufferbloat.net  # needs netperf, see [S10]
   ```
   The waveform test needs only a browser: <https://www.waveform.com/tools/bufferbloat> [S6].
   Target: added RTT ≤ 20 ms over the 0.933 ms idle baseline.
5. **CPU cost.** With the shaper at the target rate and a bulk flow running:
   ```sh
   top -bn1 | head -12      # look at the idle line per core
   ```
   If one core sits near 100 % `si`/`sys`, the shaper is at its ceiling whatever the setting says.

## Per-host fairness

`drek` masquerades every source to its WAN address, and `etra` masquerades again toward `drek`.
With `nat`, CAKE performs a conntrack lookup to find the true addresses [S1]. But each router only
sees one NAT layer deep:

| Point                      | What CAKE `nat` resolves to                              | Consequence                                                               |
| -------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------- |
| `drek` `wan` egress        | `192.168.40.1` (etra's WAN address) for all home traffic | separates `etra`, `drek`'s own LAN and `wg0` — **not** `brys` from `oams` |
| `drek` `ifb4wan` (ingress) | the public address, and no conntrack entry for this pass | no host identity at all                                                   |
| `etra` `wan` egress        | `192.168.73.x` (the real source)                         | per-host fairness for the **upload**                                      |
| `etra` `lan` egress        | `192.168.73.x` (the real destination)                    | per-host fairness for the **download**                                    |

Evidence: `etra` sets `IPMasquerade = "ipv4"` in the router module
(`modules/den/aspects/net-router/base.nix`), and `drek`'s route table holds only the
`192.168.40.0/31` link toward `etra` [M7]. On the ingress path, `tc` runs before prerouting, so the
current pass has no conntrack entry and no DNAT [S18].

So the `dual-*` modes below are correct and useful, but on `drek` they buy **device** fairness,
not host fairness. Put the host-level policy on `etra` (see [etra.md](etra.md)).

The isolation modes, from `tc-cake(8)` [S1]:

| Mode                       | Definition                                                                            | Use here                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `triple-isolate` (default) | 5-tuple, fair over source **and** destination hosts, "and also over individual flows" | good default; already covers hosts                                                                   |
| `dual-dsthost`             | 5-tuple; fairness first over destination address, then flows                          | **download**: "prevent any one LAN host from monopolising the downlink"                              |
| `dual-srchost`             | 5-tuple; fairness first over source address, then flows                               | **upload**: "prevent any one LAN host from monopolising the uplink"                                  |
| `hosts`                    | source-destination host pairs only; ignores ports                                     | coarser. Use only if you want host pairs to share one queue. It **cannot** be combined with `dual-*` |

The task brief says "`triple-isolate` + `host` isolation". They are alternatives, not layers:
`triple-isolate` already includes host-level fairness, and `hosts` replaces per-flow fairness with
per-host fairness. The strongest setting for a NAT router is the directional pair — and that is
also the recipe a real E8450 user reported working [S5]:

```
iqdisc_opts  'ingress nat dual-dsthost'
eqdisc_opts  'egress  nat dual-srchost ack-filter'
```

`ack-filter` cuts upload ACK traffic. It is safe on the egress side and helps on a slow uplink.

A per-host **ceiling** (not just fairness) still needs a mark. Two ways:

- Set CS1 on the bulk host's traffic and keep `diffserv3` on egress. The Bulk tin gets 6.25 % of
  the threshold and yields to everything else [S1].
- Skip marks and cap the host at `etra` with the HTB tree (piece C in [etra.md](etra.md)).
  This is the only option that also works for **download**, because SQM washes inbound DSCP and
  because `drek` cannot see the host.

Keep `dual-dsthost`/`dual-srchost` in the `wan` configuration anyway: they are free, and they stop
one downstream device (for example a `wg0` client or `drek`'s own LAN) from starving `etra`.

## Proposed configuration

`uci` values for the `wan` instance. Every key is one that `/usr/lib/sqm/run.sh` reads
(`config_get "$section" <key>`), verified on the device.

```sh
uci -q delete sqm.eth1
uci set sqm.wan=queue
uci set sqm.wan.enabled='1'
uci set sqm.wan.interface='wan'
uci set sqm.wan.download='400000'        # 400 Mbit/s, from the ramp test
uci set sqm.wan.upload='100000'          # from the upload measurement
uci set sqm.wan.qdisc='cake'
uci set sqm.wan.script='layer_cake.qos'
uci set sqm.wan.linklayer='ethernet'     # wan has a static /30, so no PPPoE
uci set sqm.wan.overhead='38'            # ethernet: preamble + IFG + FCS
uci set sqm.wan.tcMPU='84'               # NOT "mpu": the key is tcMPU
uci set sqm.wan.iqdisc_opts='ingress nat dual-dsthost'
uci set sqm.wan.eqdisc_opts='egress nat dual-srchost ack-filter'
uci set sqm.wan.ingress_ecn='ECN'
uci set sqm.wan.egress_ecn='ECN'
uci commit sqm
/etc/init.d/sqm restart
```

Four details that the code, not the docs, decides:

- `wan` carries a static `94.240.3.230/30` address, so the link is plain Ethernet, not PPPoE
  [M7].
- With `qdisc='cake'`, `sqm-scripts` builds the link-layer string from **`overhead` and
  `tcMPU` only** (`get_cake_lla_string` in `/usr/lib/sqm/functions.sh`). The `ethernet` keyword of
  `tc-cake(8)` expands to `overhead 38 mpu 84` [S1], but SQM does not pass the `mpu 84` part for
  you. Set `tcMPU` yourself.
- `linklayer` must be something other than `none`, or the overhead string is skipped entirely
  (`if [ "${TMP_LLAM}" = "cake" -a "${LINKLAYER}" != "none" ]`).
- `qdisc_advanced` and `qdisc_really_really_advanced` are LuCI display flags. They change nothing
  in `tc`. They are left out on purpose.

The `tc` that this produces, for checking by hand:

```sh
tc -s qdisc show dev wan
tc -s qdisc show dev ifb4wan
# expected shape of the ingress line:
#   qdisc cake … bandwidth 400Mbit diffserv3 dual-dsthost ingress nat …
```

Apply it in two passes. Start with `script='piece_of_cake.qos'` (one tin) and prove the rate and
the latency. Then switch `script` to `layer_cake.qos` and add the `iqdisc_opts`/`eqdisc_opts`
above. If the second pass breaks something, the first pass is the known-good state.

Before you commit to it, prove that the shipped `tc-tiny` accepts these keywords. `tc-tiny` is a
size-reduced build, and a rejected keyword fails the whole `sqm` start. Test on a spare device,
not on `wan`:

```sh
ip link add probe-ifb type ifb
tc qdisc add dev probe-ifb root cake bandwidth 100Mbit ingress nat dual-dsthost
tc -s qdisc show dev probe-ifb
tc qdisc del dev probe-ifb root
ip link delete probe-ifb
```

If a keyword is rejected, install the full `tc` package (`opkg install tc`) and point
`/sbin/tc` at it. Do not edit `/usr/lib/sqm/*.qos` to work around a parse error.

## Steps and rollback

Ordered. Each step has a rollback that returns the device to `noqueue`.

1. Turn off hardware flow offload only:
   ```sh
   uci set firewall.@defaults[0].flow_offloading_hw='0'
   uci commit firewall && /etc/init.d/firewall restart
   ```
   Cost: throughput without any shaper drops. Measure before and after. That drop is the price of
   a qdisc on the path, and it is why step 2 exists.
2. Prove a plain `tbf` holds a rate, using the differential counter test:
   ```sh
   tc qdisc replace dev wan root tbf rate 300mbit burst 4mbit latency 40ms
   # … run the 30 s transfer, compare counters …
   tc qdisc del dev wan root
   ```
3. Ramp CAKE to find the ceiling. Start at 300 Mbit, then 400, 450, 500. At each step record the
   delivered rate, the `tc -s` `av_delay`, and the CPU idle. Stop at the first step that misses
   90 % of its own setting.
4. Apply the `uci` block above with the measured numbers.
5. Re-measure all three targets in [definition.md](definition.md#acceptance-test).

Rollback, in one command per level:

```sh
/etc/init.d/sqm stop && uci set sqm.wan.enabled='0' && uci commit sqm   # shaper off
uci set firewall.@defaults[0].flow_offloading_hw='1' && uci commit firewall \
  && /etc/init.d/firewall restart                                        # offload back on
tc qdisc del dev wan root 2>/dev/null; tc qdisc del dev wan ingress 2>/dev/null
ip link del ifb4wan 2>/dev/null                                          # last resort
```

Do not reboot `drek` to roll back. The clock is 38 days behind and the boot waits on a missing
`/mnt/diablo` [definition.md](definition.md#pre-existing-defects-record-do-not-fix-here).

## Risks

- **The line is faster than the CPU.** 1 Gbit/s port, ~420 Mbit/s of CAKE. Option S exists for
  this reason, and it must be chosen with a measurement, not a guess.
- **`flow_offloading_hw=0` costs throughput.** Without offload, the MT7622 routing path is slower.
  Measure it. If the loss is large, Option S again: no download shaper on `drek` means no need to
  disable offload for the download direction.
- **`wash` is on by default for ingress.** Any DSCP-based bulk class you build on the LAN side
  dies at the border. Use per-host fairness or per-host caps instead.
- **`tc-tiny` may reject keywords.** Test before applying, as shown above.
- **The clock is wrong by 38 days.** Compare durations, never timestamps.
- **RAM is 489 MiB, not 512.** CAKE's `memlimit` is derived from bandwidth and RTT [S1]; at
  400 Mbit/s it is small, but this device has no room for a second large queue set. Do not run
  `cake` on `lan` bridges as well.

## Sources

- **[S1]** `tc-cake(8)` — <https://man7.org/linux/man-pages/man8/tc-cake.8.html>
- **[S4]** `sqm-scripts` README — <https://github.com/tohojo/sqm-scripts>
- **[S5]** `sqm-scripts` issue #142, E8450/MT7622BV report and the `iqdisc_opts`/`eqdisc_opts`
  recipe — <https://github.com/tohojo/sqm-scripts/issues/142>
- **[S6]** Bufferbloat project, "What Can I Do About Bufferbloat?" —
  <https://www.bufferbloat.net/projects/bloat/wiki/What_can_I_do_about_Bufferbloat/>
- **[S7]** Bufferbloat project, "Cake Technical Information" —
  <https://www.bufferbloat.net/projects/codel/wiki/CakeTechnical/>
- **[S10]** Flent documentation — <https://flent.org/intro.html>
- **[S11]** IRTT README — <https://github.com/heistp/irtt>
- **[S12]** OpenWrt wiki, "SQM (Smart Queue Management)" — the hardware-offload incompatibility
  sentence was read from the search-result excerpt, because the page is behind a bot check:
  <https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm>
- **[S13]** OpenWrt forum and Reddit reports on this board (excerpts read 2026-11-19):
  <https://forum.openwrt.org/t/belkin-rt3200-linksys-e8450-wifi-ax-discussion/94302?page=68>,
  <https://www.reddit.com/r/openwrt/comments/z9r8ql/rt3200e8450_low_sqm_cake_performance/>
- **[S14]** OpenWrt device page, "Linksys E8450 (aka. Belkin RT3200)" —
  <https://openwrt.org/toh/linksys/e8450>
- **[S15]** Köppeler et al., LANMAN 2025, `cake_mq` — cited by [S1]. Not read (PDF parse failed).
- **[S17]** FreshTomato wiki, "Bandwidth Limiter" (85 % of a three-test average, three tests at
  different hours) — <https://wiki.freshtomato.org/doku.php/bwlimit>
- **[S18]** nftables wiki, "Netfilter hooks" — ingress and `tc` ingress act before prerouting,
  conntrack sits at priority -200 and destination NAT at -100:
  <https://wiki.nftables.org/wiki-nftables/index.php/Netfilter_hooks>
