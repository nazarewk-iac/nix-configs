{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.rambox;
in {
  options.kdn.programs.rambox = {
    enable = lib.mkEnableOption "rambox setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.apps."rambox" = {
          enable = true;
          dirs.cache = [];
          dirs.config = ["rambox"];
          dirs.data = [];
          dirs.disposable = [];
          dirs.reproducible = [];
          dirs.state = [];
        };
      }
    ]
  );
}
