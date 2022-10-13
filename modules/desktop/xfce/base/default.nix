{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.xfce.base;
in
{
  options.kdn.xfce.base = {
    enable = mkEnableOption "gnome base setup";
  };

  config = mkIf cfg.enable {
    services.xserver.desktopManager.xfce.enable = true;
    programs.thunar.plugins = with pkgs; [
      xfce.thunar-archive-plugin
      xfce.thunar-volman
    ];


    environment.gnome.excludePackages = with pkgs.gnome; [
      gnome-terminal
      nautilus
      sushi
    ];
  };
}
