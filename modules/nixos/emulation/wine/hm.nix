{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.emulation.wine;
in {
  options.kdn.emulation.wine = {
    enable = lib.mkEnableOption "Wine";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps.wine = {
          enable = true;
          package.original = pkgs.wine-wayland;
          dirs.cache = [];
          dirs.config = [];
          dirs.data = ["/.wine"];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
