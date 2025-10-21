{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.chromium;
in
{
  options.kdn.programs.chromium = {
    enable = lib.mkEnableOption "chromium setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.programs.apps.chromium = {
          enable = true;
          package.original = pkgs.ungoogled-chromium;
          dirs.cache = [ ];
          dirs.config = [ "chromium" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ]
  );
}
