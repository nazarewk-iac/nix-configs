{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.etra;

  rCfg = config.kdn.networking.router;
  netconf = config.kdn.security.secrets.placeholders.networking;

  ula = {
    network = "fd12:ed4e:366d::";
    netmask = "48";
    lan = {
      network = "fd12:ed4e:366d:8::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:8::1";
    };
    pic = {
      network = "fd12:ed4e:366d:9::";
      netmask = "64";
      address.gateway = "fd12:ed4e:366d:9::1";
    };
  };
  net.ipv4.p2p.drek-etra = {
    network = "192.168.40.0";
    netmask = "31";
    address.gateway = "192.168.40.0";
    address.client = "192.168.40.1";
  };
  ll.drek.br-etra = "fe80::c641:1eff:fef8:9ce7";
  ll.etra.br-etra = "fe80::b47b:911a:2d95:d12f";
  vlan.pic.name = "pic";
  vlan.pic.id = 1859;

  mac.cafal.default = "00:23:79:00:31:03";
in
{
  options.kdn.profile.host.etra = {
    enable = lib.mkEnableOption "etra host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # TODO: setup the dedicated YubiKey with GPG
    # TODO: setup the dedicated YubiKey with FIDO2 authentication
    {
      # 32GB RAM total
      kdn.profile.machine.baseline.enable = true;
      kdn.profile.machine.baseline.initrd.emergency.rebootTimeout = 30;
      kdn.hardware.cpu.intel.enable = true;
      security.sudo.wheelNeedsPassword = false;

      zramSwap.enable = lib.mkDefault true;
      zramSwap.memoryPercent = 50;
      zramSwap.priority = 100;

      boot.tmp.tmpfsSize = "8G";
      boot.initrd.kernelModules = [
        "sdhci"
        "sdhci_pci"
      ];
    }
    (
      let
        cfg = config.kdn.hardware.disks;
        name = "emmc-etra";
        luksVol = cfg.luks.volumes."${name}";
      in
      {
        kdn.hardware.disks.initrd.failureTarget = "emergency.target";
        kdn.hardware.disks.enable = true;
        kdn.hardware.disks.devices."boot".path = "/dev/disk/by-id/usb-Lexar_USB_Flash_Drive_04R5Q5DX7R12U7QB-0:0";
        kdn.hardware.disks.luks.volumes."${name}" = {
          targetSpec.path = "/dev/disk/by-id/mmc-SCA128_0x061748d6";
          uuid = "696c5033-c9e8-4ce5-be8c-c9fe17566d2e";
          headerSpec.num = 2;
        };
      }
    )
    {
      kdn.networking.router.enable = true;

      kdn.networking.router.nets.wan = {
        type = "wan";
        netdev.kind = "bond";
        interfaces = [ "enp1s0" ];
        address = [ ];
        wan.asDefaultDNS = true;
        wan.dns = [
          net.ipv4.p2p.drek-etra.address.gateway
          ll.drek.br-etra
        ];
        wan.gateway = [
          net.ipv4.p2p.drek-etra.address.gateway
          ll.drek.br-etra
        ];
        template.network.sections.p2p-drek-etra.Address = with net.ipv4.p2p.drek-etra; {
          /* cannot use IPv4 link-local addressing because it causes degraded state, see:
            - https://github.com/systemd/systemd/issues/575
            - https://github.com/systemd/systemd/issues/9077
           */
          Address = "${address.client}/${netmask}";
          Peer = "${address.gateway}/${netmask}";
        };
      };

      kdn.networking.router.nets.lan = {
        type = "lan";
        lan.uplink = "wan";
        netdev.kind = "bond";
        netdev.bond.mode = "aggregate";
        interfaces = [ "enp2s0" "enp3s0" ];
        address = [
          (with ula.lan; "${address.gateway}/${netmask}")
          (with netconf.ipv6.network.etra.lan; "${address.gateway}/${netmask}")
        ];
        addressing.ipv4 = {
          id = 3236353446;
          network = "192.168.73.0";
          netmask = "24";
          pools.default.start = "192.168.73.32";
          pools.default.end = "192.168.73.255";
          hosts.etra.ip = "192.168.73.1";
          hosts.cafal.ip = "192.168.73.2";
          hosts.cafal.ident.hw-address = mac.cafal.default;
        };
        prefix.ula = with ula.lan; "${network}/${netmask}";
        prefix.public = with netconf.ipv6.network.etra.lan; "${network}/${netmask}";
      };

      kdn.networking.router.nets.pic = {
        type = "lan";
        lan.uplink = "wan";
        netdev.kind = "vlan";
        vlan.id = vlan.pic.id;
        interfaces = [ "lan" ];
        address = [
          (with ula.pic; "${address.gateway}/${netmask}")
          (with netconf.ipv6.network.etra.pic; "${address.gateway}/${netmask}")
        ];
        prefix.ula = with ula.pic; "${network}/${netmask}";
        prefix.public = with netconf.ipv6.network.etra.pic; "${network}/${netmask}";

        addressing.ipv4 = {
          id = 2332818586;
          network = "10.92.0.0";
          netmask = "16";
          pools.default.start = "10.92.0.32";
          pools.default.end = "10.92.0.255";
          hosts.etra.ip = "10.92.0.1";
          hosts.cafal.ip = "10.92.0.2";
        };
      };
    }
    {
      # accept all traffice coming from Netbird to any other routed network
      networking.firewall.trustedInterfaces = [ "nb-priv" ];
    }
    {
      kdn.networking.router.nets.wan = {
        firewall.allowedUDPPorts = [ 53 853 ];
      };
      kdn.networking.router.knot.listens = [
        net.ipv4.p2p.drek-etra.address.client
        "${ll.etra.br-etra}%wan"
      ];

      networking.firewall = {
        # syncthing ranges
        allowedTCPPorts = [ 53 853 ];
        allowedUDPPorts = [ 53 853 ];
      };
      #kdn.networking.router.knot.localAddress = "192.168.40.1";
      kdn.networking.router.domains."int.kdn.im." = { };
      kdn.networking.router.dhcp-ddns.suffix = "net.int.kdn.im.";
      services.kresd.instances = 2;
    }
    {
      kdn.networking.router.addr.public.ipv4.path = config.sops.secrets."networking/ipv4/network/isp/uplink/address/client".path;
      kdn.networking.router.addr.public.ipv6.path = config.sops.secrets."networking/ipv6/network/isp/prefix/etra/address/gateway".path;
    }
    {
      # faster rebuilds
      documentation.man.man-db.enable = false;
      documentation.man.generateCaches = false;
    }
    {
      kdn.networking.router.debug = false;
    }
  ]);
}
