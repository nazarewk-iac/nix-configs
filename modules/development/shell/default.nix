{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.shell;
in
{
  options.kdn.development.shell = {
    enable = lib.mkEnableOption "shell development";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      bash
      shellcheck
      shfmt
      zsh

      docopts

      gnumake
    ];
  };
}
