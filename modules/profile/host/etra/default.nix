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
  net.ipv4.lan = {
    network = "192.168.73.0";
    netmask = "24";
    address.gateway = "192.168.73.1";
    address.cafal = "192.168.73.2";
  };
  net.ipv4.pic = {
    network = "10.92.0.0";
    netmask = "16";
    address.gateway = "10.92.0.1";
    address.cafal = "10.92.0.2";
  };
  net.ipv4.p2p.drek-etra = {
    network = "192.168.40.0";
    netmask = "31";
    address.gateway = "192.168.40.0";
    address.client = "192.168.40.1";
  };
  ll.drek.br-etra = "fe80::c641:1eff:fef8:9ce7"; # drek's link-local address
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
      networking.nameservers = lib.mkForce [ ];
      kdn.networking.router.enable = true;
      #kdn.networking.router.debug = true;

      kdn.networking.router.nets.wan = {
        type = "wan";
        netdev.kind = "bond";
        interfaces = [ "enp1s0" ];
        address = [ ];
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
        netdev.kind = "bridge";
        interfaces = [ "enp3s0" ];
        firewall.trusted = false;
        address = [
          (with net.ipv4.lan; "${address.gateway}/${netmask}")
          (with ula.lan; "${address.gateway}/${netmask}")
          (with netconf.ipv6.network.etra.lan; "${address.gateway}/${netmask}")
        ];
        prefix.ula = with ula.lan; "${network}/${netmask}";
        prefix.public = with netconf.ipv6.network.etra.lan; "${network}/${netmask}";
      };

      kdn.networking.router.nets.pic = {
        type = "lan";
        lan.uplink = "wan";
        netdev.kind = "vlan";
        vlan.id = vlan.pic.id;
        interfaces = [ "lan" ];
        firewall.trusted = false;
        address = [
          (with net.ipv4.pic; "${address.gateway}/${netmask}")
          (with ula.pic; "${address.gateway}/${netmask}")
          (with netconf.ipv6.network.etra.pic; "${address.gateway}/${netmask}")
        ];
        prefix.ula = with ula.pic; "${network}/${netmask}";
        prefix.public = with netconf.ipv6.network.etra.pic; "${network}/${netmask}";
      };
    }
    (
      let host = "cafal"; nets = [ "lan" "pic" ]; in {
        kdn.networking.router.nets = lib.pipe nets [
          (builtins.map (netName: {
            name = netName;
            value.dhcpv4.leases = [{
              mac = mac."${host}".default;
              ip = net.ipv4."${netName}".address."${host}";
            }];
          }))
          builtins.listToAttrs
        ];
      }
    )
  ]);
}
