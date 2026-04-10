{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.shell = {
            enable = lib.mkEnableOption "shell development";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.shell;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            programs.helix.extraPackages = with pkgs; [
              bash-language-server
              shellcheck
              shfmt

              cmake-language-server
            ];
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.shell;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.development.shell.enable = true;}];
            environment.systemPackages = with pkgs; [
              bash
              shellcheck
              shfmt
              zsh

              docopts # https://github.com/docopt/docopts
              bats # https://github.com/bats-core/bats-core

              gnumake

              expect
            ];
          };
        }
      )
    )
  ];
}
