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
      /*
      TODO: 2025-06-26: didn't build
      */
      programs.helix.enable = false;
      programs.helix.settings.theme = "darcula-solid";
      stylix.targets.helix.enable = false;
    }
    (lib.mkIf config.kdn.desktop.enable {
      kdn.development.jetbrains.enable = true;
    })
  ]);
}
