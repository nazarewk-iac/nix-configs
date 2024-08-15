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
      kdn.networking.router = {
        enable = true;
        debug = true;
        wan.type = "static";
        wan.static.networks = [ "lan-drek-ipv4" "through-drek-ipv6" ];
        lan.static.networks = [ "lan-ipv4" "lan-ipv6" ];
        interfaces."enp1s0".role = "wan-primary";
        interfaces."enp2s0".role = "lan";
        interfaces."enp3s0".role = "lan";
      };
    }
  ]);
}
