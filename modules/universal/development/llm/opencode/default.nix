{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.llm.opencode;
in
{
  options.kdn.development.llm.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI harness";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.development.llm.opencode = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifHM {
        kdn.apps.opencode = {
          enable = true;
          package.original = pkgs.opencode;
          # opencode follows the XDG base directory specification.
          dirs.config = [ "opencode" ];
          dirs.data = [ "opencode" ];
          dirs.cache = [ "opencode" ];
          dirs.state = [ "opencode" ];
        };
      })
    ]
  );
}
