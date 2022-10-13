{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.headless;
in
{
  options.kdn.headless = {
    enableGUI = mkEnableOption "tells the rest of configs to enable/disable GUI applications";
  };

  config = {
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
