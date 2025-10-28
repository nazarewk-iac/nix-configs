{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.host.kdn-rpi4-bootstrap;
in {
  options.kdn.profile.host.kdn-rpi4-bootstrap = {
    enable = lib.mkEnableOption "enable kdn-rpi4-bootstrap host profile";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = kdnConfig.features.rpi4 -> cfg.enable;
            message = ''`kdn.profile.host.kdn-rpi4-bootstrap.enable` requires Raspberry Pi 4 profile.'';
          }
          {
            assertion = kdnConfig.features.rpi4 && kdnConfig.features.installer -> cfg.enable;
            message = ''`kdn.profile.host.kdn-rpi4-bootstrap.enable` requires Raspberry Pi 4 installer profile.'';
          }
        ];
      }
      {
        kdn.profile.machine.baseline.enable = true;
        security.sudo.wheelNeedsPassword = false;
      }
    ]
  );
}
