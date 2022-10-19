{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.development.shell;
in
{
  options.kdn.development.shell = {
    enable = lib.mkEnableOption "shell development";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bash
      shellcheck
      shfmt
      zsh

      gnumake
    ];
  };
}
