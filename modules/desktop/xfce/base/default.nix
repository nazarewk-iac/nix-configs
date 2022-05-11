{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.xfce.base;
in {
  options.nazarewk.xfce.base = {
    enable = mkEnableOption "gnome base setup";
  };

  config = mkIf cfg.enable {
    # TODO: figure out why thunar.service does not consume session environment
    services.xserver.desktopManager.xfce.enable = true;
    services.xserver.desktopManager.xfce.thunarPlugins = with pkgs; [
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
