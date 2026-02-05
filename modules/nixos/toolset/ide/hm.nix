{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.ide;
in {
  options.kdn.toolset.ide = {
    enable = lib.mkEnableOption "IDEs utils";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.programs.terminal-ide.enable = true;
    }
    (lib.mkIf config.kdn.desktop.enable {
      kdn.development.jetbrains.enable = true;
    })
  ]);
}
