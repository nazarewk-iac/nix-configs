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

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [
      {
        programs.helix.enable = true;
        programs.helix.settings.theme = "darcula-solid";
        stylix.targets.helix.enable = false;
      }
      (lib.mkIf config.kdn.headless.enableGUI {
        kdn.development.jetbrains.enable = true;
      })
    ];
  };
}
