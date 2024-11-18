{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.golang;
  home = config.home.homeDirectory;
in {
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.development.jetbrains.go.enable = true;
    }
    {
      systemd.user.tmpfiles.rules = [
        "d ${config.xdg.cacheHome}/go - - - -"
        "L ${home}/go - - - - ${config.xdg.cacheHome}/go"
      ];

      home.persistence."usr/cache".directories = [
        ".cache/go"
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
