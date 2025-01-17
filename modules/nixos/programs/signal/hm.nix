{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.signal;
in {
  options.kdn.programs.signal = {
    enable = lib.mkEnableOption "signal setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.apps."signal-desktop" = {
        enable = true;
        #package.original = pkgs."app";
        dirs.cache = [];
        dirs.config = ["Signal"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
