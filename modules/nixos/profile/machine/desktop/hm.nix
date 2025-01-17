{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.desktop;
in {
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
    }
  ]);
}
