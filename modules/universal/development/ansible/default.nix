{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.ansible;
in
{
  options.kdn.development.ansible = {
    enable = lib.mkEnableOption "Ansible development suite";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.helix.extraPackages = with pkgs; [
          #ansible-language-server
        ];
      }
    ))
    (kdnConfig.util.ifTypes [ "nixos" ] (
      lib.mkIf cfg.enable {
        home-manager.sharedModules = [ { kdn.development.ansible.enable = true; } ];
        environment.systemPackages = with pkgs; [
          ansible
        ];
      }
    ))
  ];
}
