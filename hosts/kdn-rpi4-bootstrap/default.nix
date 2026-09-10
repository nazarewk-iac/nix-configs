{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
{
  # Every host imports this tree itself -- `flake.hostConfigurations` puts only the host
  # directory into `modules`, and `modules/meta` adds nothing. Without this line neither
  # `kdn.*` nor `home-manager` exists, and the `home-manager.sharedModules` below fails with
  # `The option `home-manager' does not exist`. This host carried no `imports`, so it had never
  # evaluated. Measured 2026-09-10. Compare `hosts/brys/default.nix:126`.
  imports = [ kdnConfig.self.nixosModules.default ];

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = kdnConfig.features.rpi4;
          message = "requires Raspberry Pi 4 profile.";
        }
        {
          assertion = kdnConfig.features.rpi4 && kdnConfig.features.installer;
          message = "requires Raspberry Pi 4 installer profile.";
        }
      ];
    }
    {
      kdn.hostName = "kdn-rpi4-bootstrap";

      system.stateVersion = "25.05";
      home-manager.sharedModules = [ { home.stateVersion = "25.05"; } ];
      networking.hostId = "9751227f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      kdn.profile.machine.baseline.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
  ];
}
