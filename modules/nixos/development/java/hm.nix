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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        programs.java.enable = true;
        programs.java.package = pkgs.jdk;

        home.packages = with pkgs; [
          maven
          # gradle-completion # TODO: 2025-10-21 source failed

          (gradle-packages.gradle_7.override {
            javaToolchains = [
              jdk8
              jdk11
              jdk17
            ];
          })
        ];
      }
      {
        systemd.user.tmpfiles.rules = [
          "d ${config.xdg.cacheHome}/gradle - - - -"
          "L ${home}/.gradle - - - - ${config.xdg.cacheHome}/gradle"
        ];

        kdn.hw.disks.persist."usr/cache".directories = [
          ".cache/gradle"
        ];
      }
    ]
  );
}
