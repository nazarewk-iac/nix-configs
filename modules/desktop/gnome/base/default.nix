{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.gnome.base;
in
{
  options.kdn.gnome.base = {
    enable = mkEnableOption "gnome base setup";
  };

  config = mkIf cfg.enable {
    services.xserver.desktopManager.gnome.enable = true;
    # see https://github.com/nazarewk/nixpkgs/blob/32096899af23d49010bd8cf6a91695888d9d9e73/nixos/modules/services/x11/desktop-managers/gnome.nix#L471-L531
    services.gnome.core-utilities.enable = true;

    # see https://github.com/nazarewk/nixpkgs/blob/32096899af23d49010bd8cf6a91695888d9d9e73/nixos/modules/services/x11/desktop-managers/gnome.nix#L319-L376
    services.gnome.core-os-services.enable = true;
    environment.systemPackages = with pkgs; [
      gnome.dconf-editor
    ];

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
      gnome-software
      gnome-weather
      nautilus
      pkgs.gnome-connections
      pkgs.gnome-photos
      totem
      yelp
    ];

    services.gvfs.enable = true; # Mount, trash, and other functionalities
  };
}
