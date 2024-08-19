{ config, pkgs, lib, modulesPath, ... }:
let
  cfg = config.kdn.profile.machine.hetzner;
in
{
  options.kdn.profile.machine.hetzner = {
    enable = lib.mkEnableOption "enable hetzner machine profile";

    ipv6Address = lib.mkOption {
      type = with lib.types; str;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.baseline.enable = true;

      # BOOT
      boot.initrd.availableKernelModules = [
        "ata_piix"
        "virtio_pci"
        "virtio_scsi"
        "xhci_pci"
        "sd_mod"
        "sr_mod"
      ];
      boot.kernelModules = [ ];

      # TODO: not sure whether it's mandatory to use grub on Hetzner?
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.loader.grub.enable = true;
      # conflict in specialisation.boot-debug
      boot.loader.grub.splashImage = lib.mkForce null;
      boot.loader.grub.device = "/dev/sda";

      fileSystems."/" = {
        device = "/dev/sda1";
        fsType = "ext4";
      };
    }
    {
      networking.useNetworkd = true;
      networking.useDHCP = true;
      networking.networkmanager.enable = false;
      systemd.network.enable = true;

      systemd.network.networks."00-wan" = {
        matchConfig.Type = "ether";
        matchConfig.Driver = "virtio_net";
        networkConfig.DHCP = "ipv4";
        networkConfig.IPv6AcceptRA = "no";
        networkConfig.IPv6SendRA = "no";
        networkConfig.LinkLocalAddressing = "ipv4";
        linkConfig.RequiredForOnline = "routable";
        # see https://docs.hetzner.com/cloud/servers/static-configuration/
        gateway = [ "fe80::1" ];
        address = lib.optional (cfg.ipv6Address != null) cfg.ipv6Address;
      };
    }
  ]);
}
