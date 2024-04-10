{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;

  exec = cmd: "exec '${cmd}'";
  playerctl = lib.getExe pkgs.playerctl;
  osd = lib.getExe' pkgs.swayosd "swayosd-client";
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    services.swayosd.enable = true;
    wayland.windowManager.sway = {
      config.keybindings = {
        # Brightness
        "XF86MonBrightnessDown" = exec "${osd} --brightness=-2";
        "XF86MonBrightnessUp" = exec "${osd} --brightness=+2";
        # Volume
        "XF86AudioRaiseVolume" = exec "${osd} --output-volume=+1";
        "XF86AudioLowerVolume" = exec "${osd} --output-volume=-1";
        "XF86AudioMute" = exec "${osd} --output-volume=mute-toggle";
        "${cfg.keys.lalt}+XF86AudioMute" = exec "${osd} --input-volume=mute-toggle";
        "XF86AudioMicMute" = exec "${osd} --input-volume=mute-toggle";
        # Media controls
        # https://www.reddit.com/r/swaywm/comments/ju1609/control_spotify_with_bluetooth_headset_with_dbus/
        "--locked XF86AudioPlay" = exec "${playerctl} play-pause";
        "--locked XF86AudioPause" = exec "${playerctl} play-pause";
        "--locked XF86AudioNext" = exec "${playerctl} next";
        "--locked XF86AudioPrev" = exec "${playerctl} previous";
        # Misc
        "Print" = exec "${lib.getExe pkgs.flameshot} gui";
      };
    };
  };
}
