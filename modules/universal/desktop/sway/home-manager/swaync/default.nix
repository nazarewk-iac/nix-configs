{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
{
  config = lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType [ "nixos" ]) (
    let
      # already implemented in home-manager
      cfg = config.services.swaync;
    in
    lib.mkIf cfg.enable {
      xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source =
        "${cfg.package}/share/dbus-1/services/org.erikreider.swaync.service";

      wayland.windowManager.sway.config.keybindings = with config.kdn.desktop.sway.keys; {
        "${super}+N" = "exec ${lib.getExe' cfg.package "swaync-client"} -t -sw";
      };
    }
  );
}
