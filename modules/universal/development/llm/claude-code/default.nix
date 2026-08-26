{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.llm.claude-code;
in
{
  options.kdn.development.llm.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI harness";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.development.llm.claude-code = lib.mkDefault cfg; } ];
      })
      (kdnConfig.util.ifHM {
        kdn.apps.claude-code = {
          enable = true;
          package.original = pkgs.claude-code;
          dirs.data = [ "/.claude" ];
          files.config = [ "/.claude.json" ];
        };
      })
    ]
  );
}
