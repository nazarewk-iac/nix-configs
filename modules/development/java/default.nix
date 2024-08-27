{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.java;
in
{
  options.kdn.development.java = {
    enable = lib.mkEnableOption "java development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{ kdn.development.java.enable = true; }];
    programs.java.enable = true;
    programs.java.package = pkgs.jdk;

    environment.systemPackages = with pkgs; [
      maven
      gradle-completion

      (pkgs.callPackage gradle-packages.gradle_7 {
        javaToolchains = [
          jdk8
          jdk11
          jdk17
        ];
      })
    ];
  };
}
