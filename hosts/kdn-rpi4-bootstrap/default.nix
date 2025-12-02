{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = kdnConfig.features.rpi4;
          message = ''requires Raspberry Pi 4 profile.'';
        }
        {
          assertion = kdnConfig.features.rpi4 && kdnConfig.features.installer;
          message = ''requires Raspberry Pi 4 installer profile.'';
        }
      ];
    }
    {
      kdn.hostName = "kdn-rpi4-bootstrap";

      system.stateVersion = "25.05";
      home-manager.sharedModules = [{home.stateVersion = "25.05";}];
      networking.hostId = "9751227f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
  ];
}
