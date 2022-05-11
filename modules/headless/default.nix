{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.headless;
in {
  options.nazarewk.headless = {
    enableGUI = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
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