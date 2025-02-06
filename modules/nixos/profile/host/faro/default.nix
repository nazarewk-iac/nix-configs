{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.faro;
in {
  options.kdn.profile.host.faro = {
    enable = lib.mkEnableOption "enable faro host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.hardware.darwin-utm-guest.enable = true;
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
    {
      kdn.nix.remote-builder.enable = true;
    }
    {
      kdn.hw.disks.initrd.failureTarget = "rescue.target";
      kdn.hw.disks.enable = true;
      kdn.hw.disks.devices."boot".path = "/dev/vda";
      kdn.hw.disks.zpools."${config.kdn.hw.disks.zpool-main.name}".import.timeout = 300;
      kdn.hw.disks.luks.volumes."virtual-faro" = {
        targetSpec.path = "/dev/vdb";
        uuid = "4b50067d-05c4-46eb-a1e1-e0a9c6106559";
        headerSpec.num = 2;
      };
    }
  ]);
}
