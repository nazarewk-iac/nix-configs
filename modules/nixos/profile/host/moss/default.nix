{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.moss;
in {
  options.kdn.profile.host.moss = {
    enable = lib.mkEnableOption "enable moss host profile";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        /*
        # TODO: change to random IPv6, add as AAAA to CloudFlare

        ipython:
          import ipaddress, random
          def random_subnet(net, prefixlen): return ipaddress.ip_network(f"{net.network_address + (random.getrandbits(prefixlen - net.prefixlen) << (128 - prefixlen))}/{prefixlen}")

          random_subnet(ipaddress.ip_network('fd31:e17c:1234::/48'), 56)
        */
        kdn.profile.machine.hetzner.enable = true;
        kdn.profile.machine.hetzner.ipv6Address = "2a01:4f8:1c0c:56e4::1/64";
        security.sudo.wheelNeedsPassword = false;

        # TODO: anji times out on using moss as DNS resolver (port 5353)
        kdn.networking.resolved.multicastDNS = "false";
      }
      {
        kdn.networking.netbird.clients.nbt.enable = true;
      }
    ]
  );
}
