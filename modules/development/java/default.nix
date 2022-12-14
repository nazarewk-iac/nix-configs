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
      (pkgs.callPackage
        (pkgs.gradleGen {
          version = "7.5.1";
          nativeVersion = "0.22-milestone-23";
          sha256 = "sha256-9rhZaxDM5QFZHpLyKYFqpARkJPOyTXcXUbBnedWMjsQ=";
          defaultJava = jdk17;
        })
        {
          javaToolchains = [
            jdk8
            jdk11
            jdk17
          ];
        }
      )
    ];
  };
}
