{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  cfg = config.kdn.profile.host.briv;
in {
  options.kdn.profile.host.briv = {
    enable = lib.mkEnableOption "enable moss host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = kdn.features.rpi4 -> cfg.enable;
          message = ''`kdn.profile.host.briv.enable` requires Raspberry Pi 4 profile.'';
        }
        {
          assertion = !(kdn.features.rpi4 && kdn.features.installer) -> cfg.enable;
          message = ''`kdn.profile.host.briv.enable` cannot use Raspberry Pi 4 installer profile.'';
        }
      ];
    }
    {
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
    {
      # TODO: those are unlocked automatically using TPM2, switch to etra (or k8s cluster) backed Clevis+Tang unlock
      kdn.hw.disks.initrd.failureTarget = "rescue.target";
      kdn.hw.disks.enable = true;
      kdn.hw.disks.devices."boot".path = "/dev/disk/by-id/mmc-JC1S5_0x2a7357a9-part1";
      kdn.hw.disks.luks.volumes."vp4300-briv" = {
        targetSpec.path = "/dev/disk/by-id/nvme-nvme.1e4b-5650343330304c45444242323333343032303433-5669706572205650343330304c20325442-00000001";
        uuid = "4d9ecf11-98c4-4cfa-b223-d4dceef00dc4";
        headerSpec.num = 2;
      };

      kdn.hw.disks.luks.volumes."px500-briv" = {
        targetSpec.path = "/dev/disk/by-id/ata-SSDPR-PX500-512-80-G2_2Z0112153";
        uuid = "c9a44d27-fd7e-40ea-8029-5e66cafc2960";
        headerSpec.num = 3;
      };
    }
  ]);
}
