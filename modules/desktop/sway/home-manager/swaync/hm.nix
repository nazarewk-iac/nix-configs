{
  config,
  pkgs,
  lib,
  ...
}: let
  # already implemented in home-manager
  cfg = config.services.swaync;
in {
  config = lib.mkIf cfg.enable {
    xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source = "${pkgs.dunst}/share/dbus-1/services/org.erikreider.swaync.service";

    wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys; {
      "${super}+N" = "exec ${lib.getExe' cfg.package "swaync-client"} -t -sw";
    };
  };
}
