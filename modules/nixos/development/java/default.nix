{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.java;
in {
  options.kdn.development.java = {
    enable = lib.mkEnableOption "java development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{kdn.development.java.enable = true;}];
  };
}
