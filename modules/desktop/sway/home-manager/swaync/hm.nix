{ config, pkgs, lib, ... }:
let
  # already implemented in home-manager
  cfg = config.services.swaync;
in
{
  config = lib.mkIf cfg.enable {
    xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source =
      "${pkgs.dunst}/share/dbus-1/services/org.erikreider.swaync.service";
  };
}
