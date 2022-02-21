{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.development.shell;
in {
  options.nazarewk.development.shell = {
    enable = mkEnableOption "shell development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bash
      zsh
      shellcheck
      gnused
      jq
    ];
  };
}