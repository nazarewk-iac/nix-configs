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
      kdn.networking.router = let addressing = config.kdn.security.secrets.placeholders.networking.addressing; in {
        enable = true;
        debug = true;
        wan.type = "static";
        wan.dns = with addressing; [
          ipv4.gateway.drek.etra
          ipv6.gateway.drek.etra
        ];
        wan.gateway = with addressing; [
          ipv4.gateway.drek.etra
          ipv6.gateway.drek.etra
        ];
        wan.address = with addressing; [
          ipv4.address.drek.etra.etra
          ipv6.address.drek.etra.local.etra
          ipv6.address.drek.etra.public.etra
        ];

        lan.dhcpServer = with addressing; ipv4.address.etra.lan.etra;
        lan.address = with addressing; [
          ipv4.address.etra.lan.etra
          ipv6.address.etra.lan.etra
        ];
        lan.prefix = with addressing; [
          ipv6.network.etra.lan
        ];
        # TODO: backup connection through NanoKVM
        #interfaces."enp0s20f0u3".role = "wan";
        #interfaces."enp0s20f0u3".matchConfig.Model = "licheervnano";
        interfaces."enp1s0".role = "wan-primary";
        interfaces."enp2s0".role = "lan";
        interfaces."enp3s0".role = "lan";
      };
    }
  ]);
}
