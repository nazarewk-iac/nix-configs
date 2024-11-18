{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.java;
  home = config.home.homeDirectory;
in {
  options.kdn.development.java = {
    enable = lib.mkEnableOption "java development";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.user.tmpfiles.rules = [
        "d ${config.xdg.cacheHome}/gradle - - - -"
        "L ${home}/.gradle - - - - ${config.xdg.cacheHome}/gradle"
      ];

      home.persistence."usr/cache".directories = [
        ".cache/gradle"
      ];
    }
    {
      programs.helix.extraPackages = with pkgs; [
        gopls
        delve
      ];
    }
  ]);
}
