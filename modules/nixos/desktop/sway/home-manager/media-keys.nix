{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.desktop.sway;

  exec = cmd: "exec '${cmd}'";
  playerctl = lib.getExe pkgs.playerctl;
  volumectl = "${lib.getExe' pkgs.avizo "volumectl"} -d";
  lightctl = "${lib.getExe' pkgs.avizo "lightctl"} -d";
in {
  config = lib.mkIf cfg.enable {
    services.avizo.enable = true;
    services.avizo.settings = {};
    wayland.windowManager.sway = {
      config.keybindings = with config.kdn.desktop.sway.keys; {
        # Brightness
        "XF86MonBrightnessDown" = exec "${lightctl} down 2";
        "XF86MonBrightnessUp" = exec "${lightctl} up 2";
        # Volume
        "XF86AudioRaiseVolume" = exec "${volumectl} up 1";
        "XF86AudioLowerVolume" = exec "${volumectl} down 1";

        "XF86AudioMute" = exec "${volumectl} toggle-mute";
        "${lalt}+XF86AudioMute" = exec "${volumectl} -m toggle-mute";
        "XF86AudioMicMute" = exec "${volumectl} -m toggle-mute";
        # Media controls
        # https://www.reddit.com/r/swaywm/comments/ju1609/control_spotify_with_bluetooth_headset_with_dbus/
        "--locked XF86AudioPlay" = exec "${playerctl} play-pause";
        "--locked XF86AudioPause" = exec "${playerctl} play-pause";
        "--locked XF86AudioNext" = exec "${playerctl} next";
        "--locked XF86AudioPrev" = exec "${playerctl} previous";
        # Misc
        "Print" = exec "${lib.getExe pkgs.flameshot} gui";
        "--inhibited Super+Print" = exec "${lib.getExe pkgs.flameshot} gui";
      };
    };
  };
}
