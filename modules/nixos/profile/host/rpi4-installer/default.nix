{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  cfg = config.kdn.profile.host.kdn-rpi4-installer;
in {
  options.kdn.profile.host.kdn-rpi4-installer = {
    enable = lib.mkEnableOption "enable kdn-rpi4-installer host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      assertions = [
        {
          assertion = kdn.features.rpi4 -> cfg.enable;
          message = ''`kdn.profile.host.kdn-rpi4-installer.enable` requires Raspberry Pi 4 profile.'';
        }
        {
          assertion = kdn.features.rpi4 && kdn.features.installer -> cfg.enable;
          message = ''`kdn.profile.host.kdn-rpi4-installer.enable` requires Raspberry Pi 4 installer profile.'';
        }
      ];
    }
    {
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
  ]);
}
