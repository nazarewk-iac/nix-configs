{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.dconf;
in
{
  options.kdn.programs.dconf = {
    enable = lib.mkOption {
      default = config.programs.dconf.enable;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      programs.dconf.enable = true;
      home-manager.sharedModules = [{ kdn.programs.dconf.enable = true; }];
    }
  ]);
}
