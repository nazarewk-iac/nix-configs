{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.etra;
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
      systemd.network.networks."00-wan" = {
        /* cannot use IPv4 link-local addressing because it causes degraded state, see:
            - https://github.com/systemd/systemd/issues/575
            - https://github.com/systemd/systemd/issues/9077
         */
        addresses = [
          {
            addressConfig = {
              Address = "192.168.40.1/31";
              Peer = "192.168.40.0/31";
            };
          }
        ];
        networkConfig = {
          DNS = [
            "192.168.40.0"
            "fe80::c641:1eff:fef8:9ce7" # drek's link-local address
          ];
          Gateway = [
            "192.168.40.0"
            "fe80::c641:1eff:fef8:9ce7" # drek's link-local address
          ];
        };
      };
      networking.nameservers = lib.mkForce [ ];
      kdn.networking.router = let netconf = config.kdn.security.secrets.placeholders.networking; in {
        enable = true;
        debug = false;
        wan.type = "static";

        lan.dhcpServer = with netconf.ipv4.network.etra.lan; "${address.gateway}/${netmask}";
        lan.address = [
          (with netconf.ipv4.network.etra.lan; "${address.gateway}/${netmask}")
          #(with netconf.ipv6.network.etra.lan; "${address.gateway}/${netmask}")
        ];
        lan.prefix = [
          (with netconf.ipv6.network.etra.lan; "${network}/${netmask}")
        ];
        /* TODO: backup connection through NanoKVM? it could theoretically route the traffic?
            it is meant for maintenance access to NanoKVM itself, but maybe iptables could configure forwarding to WAN?
            see https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/system/updating.html#Check-via-USB-RNDIS-Network-Interface
            see https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/user_guide.html#RNDIS
        */
        #interfaces."enp0s20f0u3".role = "wan";
        #interfaces."enp0s20f0u3".matchConfig.Model = "licheervnano";
        interfaces."enp1s0".role = "wan-primary";
        #interfaces."enp2s0".role = "lan";
        interfaces."enp3s0".role = "lan";
      };
    }
  ]);
}
