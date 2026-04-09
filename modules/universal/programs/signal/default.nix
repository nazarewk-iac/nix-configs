{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.signal;
in
{
  options.kdn.programs.signal = {
    enable = lib.mkEnableOption "signal setup";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.signal = lib.mkDefault cfg; } ];
    })
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            kdn.apps."signal-desktop" = {
              enable = true;
              package.original = pkgs."signal-desktop";
              dirs.cache = [ ];
              dirs.config = [ "Signal" ];
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
