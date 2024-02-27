{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.shell;
in
{
  options.kdn.development.shell = {
    enable = lib.mkEnableOption "shell development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{ kdn.development.shell.enable = true; }];
    environment.systemPackages = with pkgs; [
      bash
      shellcheck
      shfmt
      zsh

      docopts # https://github.com/docopt/docopts
      bats # https://github.com/bats-core/bats-core

      gnumake
    ];
  };
}
