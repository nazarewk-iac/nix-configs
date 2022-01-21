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

    environment.gnome.excludePackages = with pkgs.gnome; [
      epiphany
      geary
      gnome-calendar
      gnome-clocks
      gnome-contacts
      gnome-font-viewer
      gnome-maps
      gnome-music
      gnome-screenshot
      gnome-weather
      pkgs.gnome-connections
      pkgs.gnome-photos
      totem
      yelp
    ];

    services.gvfs.enable = true; # Mount, trash, and other functionalities
    services.tumbler.enable = true; # Thumbnail support for images
  };
}
