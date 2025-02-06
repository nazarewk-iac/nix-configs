{
  config,
  pkgs,
  lib,
  isRPi4 ? false,
  isRPi4Installer ? false,
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
          assertion = isRPi4 -> cfg.enable;
          message = ''`kdn.profile.host.kdn-rpi4-installer.enable` requires Raspberry Pi 4 profile.'';
        }
        {
          assertion = isRPi4Installer -> cfg.enable;
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
