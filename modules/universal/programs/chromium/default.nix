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
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.apps.chromium = {
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
      )
    ))
  ];
}
