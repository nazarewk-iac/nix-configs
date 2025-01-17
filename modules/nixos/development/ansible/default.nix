{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.ansible;
in {
  options.kdn.development.ansible = {
    enable = lib.mkEnableOption "Ansible development suite";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{kdn.development.ansible.enable = true;}];
    environment.systemPackages = with pkgs; [
      ansible
    ];
  };
}
