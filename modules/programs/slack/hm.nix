{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.programs.slack;
in
{
  options.kdn.programs.slack = {
    enable = lib.mkEnableOption "slack setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps.slack = {
        enable = true;
        dirs.cache = [ ];
        dirs.config = [ "Slack" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
  ]);
}
