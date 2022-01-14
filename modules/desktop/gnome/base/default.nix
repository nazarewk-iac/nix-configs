{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.gnome.base;
in {
  options.nazarewk.gnome.base = {
    enable = mkEnableOption "gnome base setup";
  };

  config = mkIf cfg.enable {
    services.xserver.desktopManager.gnome.enable = true;

    environment.gnome.excludePackages = with pkgs; [
      gnome.gnome-music
      gnome.gnome-terminal
      gnome.gnome-characters
      gnome.totem
      gnome.tali
      gnome.iagno
      gnome.hitori
      gnome.atomix
      gnome-tour
      gnome.geary
    ];
  };
}
