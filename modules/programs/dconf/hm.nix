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
      kdn.programs.apps.dconf = {
        enable = true;
        package.install = false;
        dirs.cache = [ ];
        dirs.config = [ "dconf" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
  ]);
}
