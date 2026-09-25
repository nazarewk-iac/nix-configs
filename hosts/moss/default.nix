{
  config,
  pkgs,
  lib,
  kdnConfig,
  modulesPath,
  ...
}:
{
  imports = [
    kdnConfig.self.nixosModules.default
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    {
      imports = kdnConfig.self.denLib.imports {
        class = "nixos";
        aspects = [
          "ca-dag"
          "certificates"
        ];
      };
    }
  ];
  config = lib.mkMerge [
    {
      kdn.hostName = "moss";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [ { home.stateVersion = "26.05"; } ];
      networking.hostId = "550ded62"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
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
      kdn.certificates.repoRoot = kdnConfig.self;
      kdn.certificates.certs.zellij-web = {
        ca = "kdn";
        type = "tls-server";
        commonName = "moss.priv.nb.net.int.kdn.im";
        sans = [ "moss.priv.nb.net.int.kdn.im" ];
        directory = "hosts/moss/certs";
        certFile = "zellij.pub";
        keyFile = "zellij.key";
        keySource = "managed";
        owner = "kdn";
      };
    }
    {
      kdn.programs.zellij.web = {
        enable = true;
        bindAddress = "0.0.0.0";
        port = 8082;
        certFile = config.kdn.certificates.certs.zellij-web.certPath;
        keyFile = config.kdn.certificates.certs.zellij-web.keyPath;
        user = "kdn";
        firewallInterfaces = [ "nb-priv" ];
      };
    }
  ];
}
