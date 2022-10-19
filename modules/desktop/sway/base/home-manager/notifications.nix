{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.sway.base;
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    # according to Dunst FAQ https://dunst-project.org/faq/#cannot-acquire-orgfreedesktopnotifications
    # you might need to create a file in home directory instead of system-wide to select proper notification daemon
    home.file.".local/share/dbus-1/services/fr.emersion.mako.service".source = "${pkgs.mako}/share/dbus-1/services/fr.emersion.mako.service";

    home.packages = with pkgs; [
      mako
    ];
  };
}
