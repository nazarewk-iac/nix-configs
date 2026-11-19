---
type: Task
description: Scope six refinements of the live inbound WAN shaper on brys — a runtime toggle, per-host parametrisation, a reusable CLI, wider protocol coverage, combinable presets, and a precise definition of "WAN".
status: open
authored_by: agent
timestamp: 2026-11-19T12:00:00+01:00
---

# WAN shaping refinements

## Context

`hosts-den/brys/wan-shaping.nix` is committed and live on `brys`. It does one thing: it caps inbound
TCP/443 on `kdn-eth-2g` at 600 Mbit/s, so one model download cannot fill the 1 Gbit/s WAN. It works.
The numbers in [../brys-r9700-model-fit/measurements.md](../brys-r9700-model-fit/measurements.md)
("WAN shaping") support both the problem and the fix:

| fact                                | value                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------ |
| unconstrained Hugging Face download | 105 MB/s (about 845 Mbit/s)                                                                |
| `tbf` at a 300 Mbit/s setting       | 34.5 MB/s (276 Mbit/s)                                                                     |
| `tbf` at a 600 Mbit/s setting       | 68-70 MB/s (544-560 Mbit/s)                                                                |
| `trickle` (LD_PRELOAD)              | under-delivers 3x at these rates                                                           |
| `drek` (OpenWrt) shaping            | a 200 Mbit setting delivered 446 Mbit/s; its DSA counters do not report the shaped traffic |

The current shape of the module, in one block:

```text
tc qdisc replace dev kdn-eth-2g handle ffff: ingress
tc filter replace dev kdn-eth-2g parent ffff: protocol ipv6 prio 10 \
  flower ip_proto tcp src_port 443 action mirred egress redirect dev ifb-shape
tc filter replace dev kdn-eth-2g parent ffff: protocol ip prio 20 \
  flower ip_proto tcp src_port 443 action mirred egress redirect dev ifb-shape
tc qdisc replace dev ifb-shape root handle 1: tbf rate 600mbit burst 4mbit latency 40ms
```

So the real match today is **"every IPv4 or IPv6 TCP packet whose source port is 443, as far as a
`protocol ip`/`protocol ipv6` filter sees it"**, arriving on the WAN port. The source address plays
no part, and the tagged-frame question is still open (see [§ f](#f-what-is-wan-here)).

The module is a good first cut, not a finished facility. Six questions remain. Each section gives
the problem, the options and a recommendation. The commands, option sketches and tables are in
[design.md](design.md).

## a) Turn the shaping on and off at runtime

**Problem.** `rateMbit` and `iface` are Nix `let` values. Today the only documented toggle is
`systemctl disable --now kdn-wan-shaping`, which is persistent and needs root. A rate change needs a
rebuild, or a hand-written `tc` command that the unit does not know about.

**Options.**

1. **`systemctl start` / `systemctl stop`.** The unit is `oneshot` with `RemainAfterExit = true`, so
   `stop` runs the existing `down` script. This needs no rebuild and is already correct. The state
   does not survive a reboot, because the unit is `wantedBy = multi-user.target`.
2. **A config file read at start.** Nix writes the declared values to `/etc/kdn/wan-shape/<link>.json`;
   the tool merges a runtime override from `/var/lib/kdn/wan-shape/<link>.override.json`. A rate or
   an "off" flag is then a file edit plus `systemctl restart`, which keeps the value across a reboot.
3. **`tc qdisc change` in place.** `tc(8)` states that `change` modifies an entity in place and
   cannot move it, so the handle and the parent stay valid. No queue is destroyed and no filter is
   rebuilt.
4. **`ExecReload=`.** A `reload` verb applies option 3 through `systemctl reload`, so the operator
   never types `tc`.

**Recommendation.** Use 1 for the plain toggle and 4 for every parameter change. Put the runtime
override in `/var/lib/kdn/wan-shape/override.json`, and let the apply path read it, so `off` stays
off after a reboot (`ExecCondition=` or an early exit in the script). Never use `up` to change a
rate: `up` replaces the ingress qdisc, and that deletes every filter on it. Use `tc qdisc change dev
ifb-shape root tbf …` instead.

## b) Parametrize it for different hosts

**Problem.** The interface, the rate, the burst, the ifb name and the whole match are `brys`
constants in a host file. No other host can use the module, and the module ignores
`kdn.networking.iface.default` even though its own comment says that option owns the interface.

**Design.** One den aspect, `modules/den/aspects/net-wan-shaping.nix`, in the `nixos` class only
(`tc` and `ifb` are Linux facilities). Options live under `kdn.networking.wanShaping`, one entry per
link:

```nix
kdn.networking.wanShaping.links.<name> = {
  iface = config.kdn.networking.iface.default.name;  # default, override per host
  ifb = "ifb-wan";                                   # default "ifb-<link>", <= 15 characters
  direction = "ingress";                             # ingress | egress | both
  ceilingMbit = 600;                                 # shaped rate
  linkMbit = 1000;                                   # measured WAN rate, for presets and checks
  qdisc = "tbf";                                     # tbf | cake | htb
  burst = null;                                      # null = derive from ceilingMbit
  excludedSources = [ "192.168.0.0/16" "100.64.0.0/10" "fd00::/8" ];  # see § f
  flows = [ "tcp/443" "udp/443" ];                   # see § d
  preset = "bulk";                                   # see § e
};
```

Inclusion is the switch: the den tree does not use a bare `enable` option, and the aspect is inert
with no link. A host matrix, so the same aspect is not forced onto hosts where it makes no sense:

| host           | role                      | shaping?               | note                                                                      |
| -------------- | ------------------------- | ---------------------- | ------------------------------------------------------------------------- |
| `brys`         | workstation, 1 Gbit/s WAN | yes, 600 Mbit/s        | the measured case; keep today's numbers as this host's values             |
| `etra`         | router                    | yes, per-host classes  | shapes forwarded traffic for the whole LAN; needs conntrack marks (§ e)   |
| `pryll`, `orr` | workstations              | opt-in                 | same preset as `brys`                                                     |
| `oams`         | laptop                    | opt-in, off by default | changes link often (Wi-Fi, `drek` LAN, `gipe`); a fixed WAN port is wrong |
| `anji`         | macOS                     | no                     | `tc` is an iproute2 tool; Darwin is out of scope                          |
| `drek`         | OpenWrt                   | no                     | not NixOS; `sqm-scripts` owns it, if it is used at all                    |

**Recommendation.** Write the aspect with one link per host and the defaults above. Keep 600/1000 for
`brys` in the host file, not as a module default, so a new host must state its own ceiling. Guard the
rate against the 32-bit limit in `tc(8)`: tc stores rates as a 32-bit bps value, so a rate above
4 294 967 295 bit/s cannot be expressed.

## c) Wrap it as a reusable CLI for on-demand use

**Problem.** On-demand use is the real use case: "run this 100 GB download, cap it for the next
20 minutes". Today that means hand-written `tc` commands that the unit, the next reboot and the next
operator do not see.

**Design.** One script, `kdn-wan-shape`, packaged in `packages/kdn-wan-shape/` with
`writeShellApplication` and `runtimeInputs = [ iproute2 jq gawk ]`, registered in
`packages/default.nix`, and installed by the aspect through `kdn.env.packages`. The unit's three
exec lines call the same script, so the boot path and the on-demand path cannot diverge:

```ini
ExecStart  = kdn-wan-shape apply --config /etc/kdn/wan-shape/wan.json
ExecReload = kdn-wan-shape reload --config /etc/kdn/wan-shape/wan.json
ExecStop   = kdn-wan-shape clear
```

Verbs: `apply`, `reload`, `clear`, `status`, `set rate|preset|flows`, `explain`, `check`. Global
flags: `--dry-run`, `--json`, `--config`, `--link`. `apply` is idempotent; `reload` only changes
qdisc and class parameters in place. `--for 20m` schedules `systemd-run --on-active=20m
kdn-wan-shape clear` (or `restore`), so a temporary cap removes itself.

**Recommendation.** Yes. Shell, not Go: the tool is a thin, readable wrapper over `tc` and `ip`, it
must run on the host with no build step, and the module already writes shell. Keep `kdnctl` out of
it. The CLI is the only writer of tc state; the unit calls the CLI.

## d) Which other WAN protocols and setups need the same treatment

**Problem.** TCP/443 is a proxy for "bulk", not a definition. The same WAN is filled by UDP/443
(QUIC), by `ssh`/`rsync`/`ssh-ng`, by VPN and mesh tunnels, and by uploads. Each one behaves
differently under drops.

| flow                                   | visible to `tc` as                                                       | shape it?              | why                                                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| TCP/443                                | TCP, src port 443                                                        | yes, today             | the measured case                                                                                                        |
| UDP/443 (QUIC, HTTP/3)                 | UDP, src port 443                                                        | yes, first addition    | QUIC runs over UDP (RFC 9000); HTTP/3 uses it (RFC 9114). A browser download is unshaped today.                          |
| TCP/80                                 | TCP, src port 80                                                         | optional               | mostly redirects to 443; cheap to add                                                                                    |
| TCP/22 (`ssh-ng`, `scp`, `rsync`, git) | TCP, src port 22                                                         | separate preset        | bulk and interactive share the port; shape only with a `bulk-ssh` preset, never by default                               |
| WireGuard                              | outer UDP; the listen port is local, the peer's source port is arbitrary | only as a whole tunnel | "WireGuard securely encapsulates IP packets over UDP". The inner 5-tuple is encrypted, so inner ports cannot be matched. |
| NetBird mesh                           | outer WireGuard + `nb-<name>`                                            | no                     | "WireGuard-based overlay network"; mesh traffic is not WAN traffic (`nb-priv` is a separate device)                      |
| IPsec                                  | ESP (protocol 50), no ports                                              | only by protocol       | there is no port to match; a port list cannot cover it                                                                   |
| ICMP, DNS, NTP                         | —                                                                        | never                  | path-MTU discovery and every name lookup depend on them; shaping them breaks connectivity                                |

Two further setups need the same treatment and are not about a protocol:

- **IPv6.** The filters must be duplicated with `protocol ipv6`. The WAN prefix arrives by SLAAC and
  can change (`2a01:6e80::/29` today), and `brys` rotates privacy addresses
  (`IPv6PrivacyExtensions = true` in the interface aspect), so a filter on the host's own `/128`
  goes stale. Match a prefix or an interface, never a host address.
- **The upload direction.** The ingress cap does nothing for uploads. If the upstream is much
  smaller than 1 Gbit/s, an upload fills it and delays the ACKs of every download. Measure the
  upstream rate, then add an egress preset (`direction = "egress"`, the mirror of this design).

**Recommendation.** Replace "port 443" with a small **protocol class table** that has a named set of
shaped flows and an explicit unshaped default. Add UDP/443 in the first pass. Leave TCP/22 out of the
default set. Treat VPN, mesh and IPv6 as separate presets, not as extra ports.

## e) Preset configs that can be chosen, adjusted and combined

**Problem.** One number (600) and one qdisc (`tbf`) cannot express "the link is 1 Gbit/s", "this
protocol may use 300", "no host may take more than 200". The three ceilings are different objects.

**Design.** Three levels, each with the qdisc that can express it:

| level                | meaning                                                 | tool                                                               | limitation                                                              |
| -------------------- | ------------------------------------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------- |
| link ceiling         | total shaped rate, with headroom below the measured WAN | `tbf rate`, `cake bandwidth`, `htb` root class                     | `tbf` is a single FIFO; `cake` is fair per flow but has no hard classes |
| per-protocol ceiling | hard cap for one class, borrowing when idle             | `htb` class `rate` + `ceil`                                        | "rate" is a floor, "ceil" is the cap; `tbf` cannot have classes         |
| per-host ceiling     | no single LAN host takes the link                       | `htb` class per `dst_ip`, or `cake dual-dsthost` for fairness only | a hard per-host cap needs `htb`; `cake` tins are WRR shares, not caps   |

Presets are a Nix enum that expands to the parameters, plus a merge for `extraClasses`:

| preset        | link                     | protocol                     | qdisc                                                    | use                                              |
| ------------- | ------------------------ | ---------------------------- | -------------------------------------------------------- | ------------------------------------------------ |
| `off`         | —                        | —                            | —                                                        | no shaping                                       |
| `bulk`        | 600 of 1000              | TCP+UDP/443 at 600           | `tbf`                                                    | today's behaviour, plus QUIC                     |
| `interactive` | 600 of 1000              | 443 at 400, default unshaped | `cake bandwidth 600mbit diffserv4 dual-dsthost ingress`  | AQM and fairness, lower latency for shaped flows |
| `router-lan`  | 900 of 1000              | per host 200, 443 at 600     | `htb` on the ifb, `flower dst_ip` classes                | `etra`: one host cannot starve the LAN           |
| `bulk-ssh`    | as `bulk`                | plus TCP/22                  | `tbf` or `htb`                                           | large `rsync`/`nix copy` jobs                    |
| `upload`      | measured upstream × 0.95 | everything                   | `cake bandwidth … dual-srchost` on the WAN device egress | protects ACKs                                    |

**Recommendation.** Ship `off`, `bulk` and `interactive` first; they need no per-host classification.
Add `router-lan` only when `etra` gets the aspect, because it needs conntrack marks or `dst_ip`
classes and a forwarding host. Select by `preset = "…"`, adjust by overriding single fields, combine
by adding classes to the same `htb` tree (root = link ceiling, child = protocol, grandchild = host).

## f) What is "WAN" here?

**Problem.** The current filter has no notion of WAN. It matches a source port. That includes the
untagged LAN, which shares `192.168.73.0/24` with the WAN port, and it excludes everything that is
not TCP/443. The module comment says "LAN traffic, SSH, the llama-swap API and outbound requests are
untouched"; that is true for SSH and outbound, but not proven for the LAN.

**The WAN on `brys`, stated as data.**

| what          | value                                                                                                                     | source                                                                          |
| ------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| WAN device    | `kdn-eth-2g`, untagged, DHCP; also carries VLANs 946/1859/3547 as sub-interfaces                                          | `hosts-den/brys/default.nix`, `modules/den/aspects/net-interfaces.nix`          |
| WAN IPv4      | a DHCP lease in `192.168.73.0/24` (`etra` is `.1`)                                                                        | `data/network-topology.md`                                                      |
| WAN IPv6      | SLAAC from the ISP prefix `2a01:6e80::/29`, one `/64` per VLAN                                                            | task brief; `IPv6AcceptRA = true` in `modules/universal/networking/default.nix` |
| internal ULA  | `fd12:ed4e:366d::/48`                                                                                                     | observed on `enp4s0` and `pic`                                                  |
| LAN, untagged | `192.168.73.0/24`                                                                                                         | `data/network-topology.md`                                                      |
| LAN, tagged   | `192.168.252.0/24` (mgmt), `192.168.41.0/24` (drek lan), `10.92.0.0/24` (pic)                                             | `data/network-topology.md`                                                      |
| CGNAT         | `100.64.0.0/10` (RFC 6598)                                                                                                | RFC 6598                                                                        |
| NetBird mesh  | `100.79.0.0/16` (inside CGNAT), `fd31::/32` (brief; `fd31:e17c:f07f::/48` observed), `nb-priv` also carries a `fdb8::/64` | `docs/netbird-dns-zones.md`, observed addresses                                 |
| never WAN     | `127.0.0.0/8`, `169.254.0.0/16`, `fe80::/10`, `ff00::/8`, `::1/128`, multicast                                            | RFC 1918, RFC 4291, RFC 3927                                                    |

**Two ways to narrow the match.**

1. **Exclude by source.** Add high-priority (low `prio`) `flower` filters that `action pass` every
   local, CGNAT, ULA, link-local and multicast source, then the shaped filters below them. The
   documented `flower` match list has no negation, so filter order is the way to get one:
   `tc-actions(8)` defines `pass` as "return to the calling qdisc … and end classification of this
   packet". This does not depend on the frame being untagged: a tagged frame that the filter cannot
   see is also unshaped. It survives a CGNAT WAN address, because the address that matters (the
   host's own) is a destination, not a source.
2. **Include by destination.** Match `dst_ip` = the host's own WAN address (`/32`) plus the ISP
   prefix. This is exact, but it breaks when the address is dynamic, and on `brys` the v4 WAN
   address sits in the same `/24` as the LAN, so a `/32` is the only usable form. It also does not
   exclude a LAN host that connects to that address.

**Recommendation.** Use 1, plus a final explicit `pass` default. Keep the port match only as the
protocol selector. Do **not** exclude `100.64.0.0/10` by destination: a CGNAT WAN address is a
legitimate destination, and excluding it would silently disable shaping on a CGNAT uplink. The
source-side exclusion is safe, because no internet source is routable in `100.64.0.0/10`.

Two details must be measured, not assumed:

- **Tagged frames.** `tc-flower(8)` states that layer-3 matches depend on the `protocol` option of
  the filter, and it offers `vlan_ethtype` for tagged frames. So a `protocol ip` filter probably
  does not match an 802.1Q frame on the parent device, which would mean the tagged VLANs are already
  outside the match and only the untagged LAN needs the source exclusion. Settle it with `tc -s
filter show`: run one HTTPS transfer from a tagged VLAN host and read the hit counter.
- **The untagged LAN.** `192.168.73.0/24` is both the LAN and the WAN L2 segment. If any host there
  downloads over HTTPS from `brys`, the current filter shapes it. Today that is latent, not active:
  the `brys` firewall opens no TCP/443 on `kdn-eth-2g` (only 39701), so no HTTPS server answers
  there. The source exclusion (`192.168.0.0/16`) closes the case before something starts to listen.

## Ranked plan

Each step leaves the host working. Do not start a later step before the earlier one has a measured
acceptance result.

1. **Make the current module honest and observable.** Add filter and qdisc counters to the report
   path (`tc -s filter`, `tc -s qdisc`), fix the burst derivation (the comment "4 Mbit … is ~0.8 ms"
   is wrong: 4 Mbit at 600 Mbit/s is 6.7 ms), and fix the boot race (`after = [ "network.target" ]`
   does not mean the interface exists). Acceptance: a fresh boot needs no manual restart, even when
   the unit starts before the interface exists.
2. **Narrow the match (§ f).** Add the source-exclusion pass filters, the explicit default pass, and
   the UDP/443 filters. Acceptance: `tc -s filter` shows zero shaped packets for a LAN transfer and
   non-zero for an internet download; the download rate stays within 10 % of today's.
3. **One code path and a runtime toggle (§ a, § c).** Package `kdn-wan-shape`, move the unit's exec
   lines onto it, add `reload` and the runtime override file. Acceptance: `systemctl reload` changes
   the rate with no filter loss and no measurable packet drop; `--for 1m` restores the previous
   state.
4. **Parametrize as a den aspect (§ b).** Move the file to `modules/den/aspects/net-wan-shaping.nix`,
   add the link options, read `kdn.networking.iface.default.name`, register it in
   `modules/den/lib.nix`, and point `brys` at it. Acceptance: `brys` produces the same qdisc, the
   same filters and the same 600 Mbit/s; a second host builds with its own values.
5. **Presets (§ e).** Add `off`, `bulk`, `interactive`. Acceptance: each preset reaches its ceiling
   within 10 % and returns the link to full rate when cleared; `cake` lowers the delay of shaped
   flows relative to `tbf` at the same rate (measure with `ping` beside a download).
6. **The remaining flows (§ d).** Upload direction, `bulk-ssh`, and a router preset for `etra`.
   Acceptance: an upload cannot starve a download's ACKs; `etra` caps one host without capping the
   others.
7. **Research only.** A per-cgroup budget, if "shape the model download" should mean the process and
   not the port. `net_cls` is a cgroup v1 controller (`net_cls` kernel doc) and its classid reads
   zero on a cgroup v2-only host (`nft(8)`, `meta cgroup`). The cgroup v2 routes are an eBPF
   classifier in `tc` (`BPF_PROG_TYPE_SCHED_CLS` plus a cgroup helper) or nftables `socket cgroupv2`
   plus a mark. Both need a prototype before they can enter the plan.

## Open questions to measure

1. Does a `protocol ip` ingress filter see 802.1Q frames on `kdn-eth-2g`? (`tc -s filter show`.)
2. What is the real upstream rate of the WAN? A 1 Gbit/s downlink does not imply a 1 Gbit/s uplink.
3. Would `drek` with `sqm-scripts` make host shaping unnecessary? Its DSA counters are unreliable,
   so the test must measure at the ends, not on the router.
4. What is the RTT and the BDP on the path to Hugging Face? It sets a sane `burst` and `latency`.
5. Does `brys` accept an ingress qdisc on a WireGuard peer device (`nb-priv`) if a mesh preset is
   ever needed? `mirred` is documented for device redirect, but not for this device type.

## Sources

Man pages and kernel documentation:

- `tc(8)` — ingress qdisc, `change` in place, 32-bit rate limit.
  <https://man7.org/linux/man-pages/man8/tc.8.html>
- `tc-tbf(8)` — non-work-conserving shaper, burst versus `rate/HZ`, `latency` as queue limit,
  millisecond-scale burstiness above ~1 Mbit/s.
  <https://man7.org/linux/man-pages/man8/tc-tbf.8.html>
- `tc-cake(8)` — `bandwidth`, `ingress` mode (counts dropped packets as transferred), `diffserv4`,
  `dual-dsthost`, `rtt`, `autorate-ingress`, `fwmark` tin override, WRR tins are shares.
  <https://man7.org/linux/man-pages/man8/tc-cake.8.html>
- `tc-htb(8)` — root class, `rate` floor, `ceil` cap, `prio`, `quantum`, `default`, leaf qdisc.
  <https://man7.org/linux/man-pages/man8/tc-htb.8.html>
- `tc-flower(8)` — match list, `ip_proto` before ports, `vlan_ethtype`, layer-3 match depends on the
  filter `protocol`.
  <https://man7.org/linux/man-pages/man8/tc-flower.8.html>
- `tc-police(8)` — policing drops instead of queueing; the ingress policing example.
  <https://man7.org/linux/man-pages/man8/tc-police.8.html>
- `tc-actions(8)` — `pass` ends classification, `continue` goes to the next filter.
  <https://man7.org/linux/man-pages/man8/tc-actions.8.html>
- `tc-mirred(8)` — `redirect` to a device, the ifb example, nesting limit, no ifb-to-ifb redirect.
  <https://man7.org/linux/man-pages/man8/tc-mirred.8.html>
- `tc-fw(8)` — the fwmark classifier.
  <https://man7.org/linux/man-pages/man8/tc-fw.8.html>
- `tc-skbedit(8)` — `priority` and `mark` edits on an skb; the cake tin override uses the priority.
  <https://man7.org/linux/man-pages/man8/tc-skbedit.8.html>
- `openssl-s_server(1)` — the temporary HTTPS listener used to prove the LAN false positive.
  <https://docs.openssl.org/master/man1/openssl-s_server/>
- `nft(8)` — `meta cgroup` reads `net_cls.classid` and reads zero on cgroup v2-only hosts; `socket
cgroupv2`; `fwd` only in the netdev family; `meta mark`.
  <https://man.archlinux.org/man/nft.8>
- Control Group v1, `net_cls` — the v1 network classifier and its `tc … cgroup` filter.
  <https://docs.kernel.org/admin-guide/cgroup-v1/net_cls.html>
- Control Group v2 — the controller list contains no `net_cls`.
  <https://docs.kernel.org/admin-guide/cgroup-v2.html>
- `bpf_skb_ancestor_cgroup_id` — the cgroup test available to a `tc` eBPF classifier.
  <https://docs.ebpf.io/linux/helper-function/bpf_skb_ancestor_cgroup_id/>
- nftables wiki, "Setting packet metainformation" — `meta mark set`, `ct mark` save and restore.
  <https://wiki.nftables.org/wiki-nftables/index.php/Setting_packet_metainformation>
- ArchWiki, "Advanced traffic control" — ingress qdiscs police but do not shape, so `ifb` is needed;
  the ingress hook sees packets before NAT; `connmark` on ingress; only `ifb` is loaded by hand.
  <https://wiki.archlinux.org/title/Advanced_traffic_control>
- `systemd.device(5)`, `systemd.unit(5)`, `systemd.service(5)` — device units for network devices,
  `BindsTo=`, `ExecCondition=`, `ConditionPathExists=`, unit-name escaping.
  <https://man7.org/linux/man-pages/man5/systemd.device.5.html>,
  <https://man7.org/linux/man-pages/man5/systemd.unit.5.html>,
  <https://man7.org/linux/man-pages/man5/systemd.service.5.html>
- `systemd-run(1)` — `--on-active=` for the self-clearing temporary cap.
  <https://man7.org/linux/man-pages/man1/systemd-run.1.html>
- NixOS manual, "Linux Kernel" — "usually loaded automatically", `boot.kernelModules` forces a load.
  <https://nixos.org/manual/nixos/stable/#sec-kernel-config>

Protocol references:

- WireGuard — "securely encapsulates IP packets over UDP". <https://www.wireguard.com/>
- NetBird — "WireGuard-based overlay network". <https://netbird.io/>
- RFC 9000, QUIC: A UDP-Based Multiplexed and Secure Transport.
  <https://www.rfc-editor.org/rfc/rfc9000.txt>
- RFC 9114, HTTP/3. <https://www.rfc-editor.org/rfc/rfc9114.txt>
- RFC 6598, IANA-Reserved IPv4 Prefix for Shared Address Space (`100.64.0.0/10`).
  <https://www.rfc-editor.org/rfc/rfc6598.txt>
- RFC 1918 (private IPv4), RFC 4193 (`fd00::/8`), RFC 4291 (`fe80::/10`), RFC 3927
  (`169.254.0.0/16`).
- OpenWrt, SQM — the `drek` alternative. <https://openwrt.org/docs/guide-user/network/traffic-shaping/sqm>

Repository references:

- The live module:
  [hosts-den/brys/wan-shaping.nix](../../../../hosts-den/brys/wan-shaping.nix)
- The measurements: [../brys-r9700-model-fit/measurements.md](../brys-r9700-model-fit/measurements.md)
- The interface options:
  [modules/den/aspects/net-interfaces.nix](../../../../modules/den/aspects/net-interfaces.nix)
- The network topology: [data/network-topology.md](../../../../data/network-topology.md)
