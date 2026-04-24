{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.chromium;
in
{
  options.kdn.programs.chromium = {
    enable = lib.mkEnableOption "chromium setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.chromium = lib.mkDefault cfg; } ];
    })
    {
      kdn.apps.chromium = {
        package.original = pkgs.ungoogled-chromium;
        dirs.cache = [ ];
        dirs.config = [ "chromium" ];
        dirs.data = [ ];
        dirs.disposable = [ ];
        dirs.reproducible = [ ];
        dirs.state = [ ];
      };
    }
    (lib.mkIf cfg.enable {
      kdn.apps.chromium.enable = true;
    })
  ];
}
