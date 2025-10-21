{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.firefox;
in
{
  options.kdn.programs.firefox = {
    enable = lib.mkEnableOption "firefox setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home-manager.sharedModules = [ { kdn.programs.firefox.enable = true; } ]; }
    ]
  );
}
