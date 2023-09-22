{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.ansible;
in
{
  options.kdn.development.ansible = {
    enable = lib.mkEnableOption "Ansible development suite";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ansible
    ];
  };
}
