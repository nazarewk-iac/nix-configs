{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.headless;
in
{
  options.nazarewk.headless = {
    enableGUI = mkEnableOption "tells the rest of configs to enable/disable GUI applications";
  };

  config = {
    home-manager.sharedModules = [
      ({ lib, ... }: {
        options.nazarewk.headless = {
          enableGUI = lib.mkOption {
            type = lib.types.bool;
            default = cfg.enableGUI;
          };
        };
      })
    ];
  };
}
