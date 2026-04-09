{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.browsers;
in
{
  options.kdn.programs.browsers = {
    enable = lib.mkEnableOption "`browsers` selector setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.browsers = lib.mkDefault cfg; } ];
    })
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.apps.browsers = {
              enable = true;
              dirs.cache = [ ];
              dirs.config = [ "software.Browsers" ];
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
