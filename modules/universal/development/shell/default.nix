{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.shell;
in
{
  options.kdn.development.shell = {
    enable = lib.mkEnableOption "shell development";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          bash
          shellcheck
          shfmt
          zsh

          docopts # https://github.com/docopt/docopts
          bats # https://github.com/bats-core/bats-core

          gnumake

          expect
        ];
      }
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [
          bash-language-server
          shellcheck
          shfmt
          cmake-language-server
        ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        home-manager.sharedModules = [ { kdn.development.shell.enable = true; } ];
      })
    ]
  );
}
