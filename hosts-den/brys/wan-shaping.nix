# Inbound-HTTPS shaping for brys.
#
# Why: a model download from Hugging Face reaches ~105 MB/s (845 Mbit/s) on this host, which is
# more than the 1 Gbit/s WAN can carry together with anything else. Every other host then sees
# stalled handshakes and "connection refused" until the download ends.
#
# What: the host caps **inbound TCP/443** at `rateMbit`. That is the download direction of every
# Hugging Face, nix-cache and browser transfer, and nothing else: LAN traffic, SSH, the llama-swap
# API and outbound requests are untouched. A model download then takes a predictable time and
# leaves the rest of the WAN free.
#
# Where: on brys itself, not on a router. Measured 2026-11-18:
#   * a tbf qdisc on an ifb device holds the rate exactly: a 300 Mbit setting delivered 34.5 MB/s;
#   * the router `drek` (OpenWrt, Cortex-A53) shapes too, but its DSA port counters do not report
#     the shaped traffic and a 200 Mbit setting delivered 446 Mbit/s, so the rate cannot be tuned
#     there reliably.
#   * `trickle` (LD_PRELOAD) under-delivered by 3x at these rates, so it is not used.
#
# `tbf` drops instead of queueing once the bucket is empty. For a bulk download that is the correct
# behaviour: TCP backs off, and the link stays useful for everybody else.
#
# Disable: `systemctl disable --now kdn-wan-shaping`.
{
  pkgs,
  ...
}:
let
  # The interface that carries the WAN traffic. Managed by `kdn.networking.iface.default`.
  iface = "kdn-eth-2g";

  # Inbound ceiling in Mbit/s. The WAN is 1 Gbit/s; 600 leaves 400 for everything else while a
  # 100 GB quant still lands in about 22 minutes.
  rateMbit = 600;

  # `tbf` needs a bucket. 4 Mbit at 600 Mbit/s is ~0.8 ms of burst, enough for one TCP window burst
  # without building a queue.
  burst = "4mbit";

  up = pkgs.writeShellScript "wan-shaping-up" ''
    set -eu
    ${pkgs.kmod}/bin/modprobe ifb 2>/dev/null || true
    ${pkgs.kmod}/bin/modprobe cls_flower 2>/dev/null || true

    # One ifb device for the redirected ingress. Recreate it, so a partially applied run heals.
    ${pkgs.iproute2}/bin/ip link show ifb-shape >/dev/null 2>&1 \
      || ${pkgs.iproute2}/bin/ip link add ifb-shape type ifb
    ${pkgs.iproute2}/bin/ip link set ifb-shape up

    # Ingress hook on the physical NIC: every TCP packet whose source port is 443 (a response from
    # an HTTPS server) is redirected into the ifb device, where the rate limiter sits.
    ${pkgs.iproute2}/bin/tc qdisc replace dev ${iface} handle ffff: ingress
    ${pkgs.iproute2}/bin/tc filter replace dev ${iface} parent ffff: protocol ipv6 prio 10 \
      flower ip_proto tcp src_port 443 action mirred egress redirect dev ifb-shape
    ${pkgs.iproute2}/bin/tc filter replace dev ${iface} parent ffff: protocol ip prio 20 \
      flower ip_proto tcp src_port 443 action mirred egress redirect dev ifb-shape

    ${pkgs.iproute2}/bin/tc qdisc replace dev ifb-shape root handle 1: \
      tbf rate ${toString rateMbit}mbit burst ${burst} latency 40ms
  '';

  down = pkgs.writeShellScript "wan-shaping-down" ''
    set -eu
    ${pkgs.iproute2}/bin/tc qdisc del dev ${iface} ingress 2>/dev/null || true
    ${pkgs.iproute2}/bin/ip link del ifb-shape 2>/dev/null || true
  '';
in
{
  systemd.services.kdn-wan-shaping = {
    description = "Cap inbound HTTPS at ${toString rateMbit} Mbit/s so a model download cannot fill the WAN";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    wants = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = up;
      ExecStop = down;
    };
  };
}
