{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: {
  options.kdn.development.ansible = {
            enable = lib.mkEnableOption "Ansible development suite";
          };

  imports = [
    ({...}:
        let
          cfg = config.kdn.development.ansible;
        in {

config = kdnConfig.util.ifHM (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable {
            programs.helix.extraPackages = with pkgs; [
              #ansible-language-server # "ansible-language-server was removed, because it was unmaintained in nixpkgs."; # Added 20
            ];
          }));
        }
      )
    (
      kdnConfig.util.ifTypes ["nixos"] (
        let
          cfg = config.kdn.development.ansible;
        in {

          config = lib.mkIf cfg.enable {
            home-manager.sharedModules = [{kdn.development.ansible.enable = true;}];
            environment.systemPackages = with pkgs; [
              ansible
            ];
          };
        }
      )
    )
  ];
}
