{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.ansible;
in
{
  options.kdn.development.ansible = {
    enable = lib.mkEnableOption "Ansible development suite";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs;[
      ansible-language-server
    ];
  };
}
