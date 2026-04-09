{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.wofi;
in
{
  options.kdn.programs.wofi = {
    enable = lib.mkEnableOption "`wofi` selector setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.wofi = lib.mkDefault cfg; } ];
    })
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.apps.wofi = {
              enable = true;
              dirs.cache = [ ];
              dirs.config = [ ];
              dirs.data = [ ];
              dirs.disposable = [ ];
              dirs.reproducible = [ ];
              dirs.state = [ ];
              files.cache = [ "wofi-run" ];
            };
          }
        ]
      )
    ))
  ];
}
