{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.golang;
in {
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.development.jetbrains.go.enable = true;
      }
      {
        #systemd.user.tmpfiles.settings.kdn-golang.rules."${config.xdg.cacheHome}/go".d = {};
        #systemd.user.tmpfiles.settings.kdn-golang.rules."%h/go".L.argument = "${config.xdg.cacheHome}/go";
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.cacheHome}/go - - - -"
          "L %h/go - - - - ${config.xdg.cacheHome}/go"
        ];

        kdn.disks.persist."usr/cache".directories = [
          ".cache/go"
        ];
      }
      {
        programs.helix.extraPackages = with pkgs; [
          gopls
          delve
        ];
      }
    ]
  );
}
