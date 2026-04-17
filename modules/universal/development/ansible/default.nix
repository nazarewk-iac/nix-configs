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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.env.packages = with pkgs; [
          ansible
        ];
      }
      (kdnConfig.util.ifHM {
        programs.helix.extraPackages = with pkgs; [
          #ansible-language-server
        ];
      })
      (kdnConfig.util.ifTypes [ "nixos" ] {
        home-manager.sharedModules = [ { kdn.development.ansible.enable = true; } ];
      })
    ]
  );
}
