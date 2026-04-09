{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.ide;
in
{
  options.kdn.toolset.ide = {
    enable = lib.mkEnableOption "IDEs utils";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.toolset.ide.enable = cfg.enable; } ];
      }
    ))
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable (
        lib.mkMerge [
          { kdn.programs.terminal-ide.enable = true; }
          (lib.mkIf config.kdn.desktop.enable {
            kdn.development.jetbrains.enable = true;
          })
        ]
      )
    ))
  ];
}
