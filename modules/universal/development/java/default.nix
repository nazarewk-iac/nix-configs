{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.java = {
            enable = lib.mkEnableOption "java development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.java;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
            lib.mkMerge [
              {
                programs.java.enable = true;
                programs.java.package = pkgs.jdk;

                home.packages = with pkgs; [
                  maven
                  # gradle-completion # TODO: 2025-10-21 source failed

                  # used to be gradle_7, but got insecure
                  (gradle-packages.gradle.override {
                    javaToolchains = [
                      jdk8
                      jdk11
                      jdk17
                    ];
                  })
                ];
              }
              {
                #systemd.user.tmpfiles.settings.kdn-java.rules."${config.xdg.cacheHome}/gradle".d = {};
                #systemd.user.tmpfiles.settings.kdn-java.rules."%h/.gradle".L.argument = "${config.xdg.cacheHome}/gradle";
                systemd.user.tmpfiles.rules = [
                  "d ${config.xdg.cacheHome}/gradle - - - -"
                  "L %h/.gradle - - - - ${config.xdg.cacheHome}/gradle"
                ];

                kdn.disks.persist."usr/cache".directories = [
                  ".cache/gradle"
                ];
              }
            ]
          )));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.java;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.development.java.enable = true;}];
          };
        }
      )
    )
  ];
}
