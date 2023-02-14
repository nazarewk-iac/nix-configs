{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.headless;
in
{
  options.kdn.headless = {
    enableGUI = lib.mkEnableOption "tells the rest of configs to enable/disable GUI applications";
  };

  config = {
    boot.kernelParams = [
      "plymouth.enable=0" # disable boot splash screen
    ];
    home-manager.sharedModules = [
      ({ lib, ... }: {
        options.kdn.headless = {
          enableGUI = lib.mkOption {
            type = lib.types.bool;
            default = cfg.enableGUI;
          };
        };
      })
    ];
  };
}
