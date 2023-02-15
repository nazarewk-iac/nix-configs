{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.java;
in
{
  options.kdn.development.java = {
    enable = lib.mkEnableOption "java development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      jdk

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
