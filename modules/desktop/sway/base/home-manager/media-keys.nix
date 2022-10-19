{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.sway.base;

  mod = import ./_modifiers.nix;
  getBinPkg = pkg: name: "${pkg}/bin/${name}";
  getBin = name: getBinPkg pkgs."${name}" name;
  exec = cmd: "exec '${cmd}'";

  brightnessctl = getBin "brightnessctl";
  pactl = getBinPkg pkgs.pulseaudio "pactl";
  playerctl = getBin "playerctl";
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    wayland.windowManager.sway = {
      config.keybindings = {
        # Brightness
        "XF86MonBrightnessDown" = exec "${brightnessctl} set 2%-";
        "XF86MonBrightnessUp" = exec "${brightnessctl} set +2%";
        # Volume
        "XF86AudioRaiseVolume" = exec "${pactl} set-sink-volume @DEFAULT_SINK@ +1%";
        "XF86AudioLowerVolume" = exec "${pactl} set-sink-volume @DEFAULT_SINK@ -1%";
        "XF86AudioMute" = exec "${pactl} set-sink-mute @DEFAULT_SINK@ toggle";
        "${mod.lalt}+XF86AudioMute" = exec "${pactl} set-source-mute @DEFAULT_SOURCE@ toggle";
        "XF86AudioMicMute" = exec "${pactl} set-source-mute @DEFAULT_SOURCE@ toggle";
        "Print" = exec "${getBin "flameshot"} gui";
        # Media controls
        # https://www.reddit.com/r/swaywm/comments/ju1609/control_spotify_with_bluetooth_headset_with_dbus/
        "--locked XF86AudioPlay" = exec "${playerctl} play-pause";
        "--locked XF86AudioPause" = exec "${playerctl} play-pause";
        "--locked XF86AudioNext" = exec "${playerctl} next";
        "--locked XF86AudioPrev" = exec "${playerctl} previous";
      };
    };
  };
}
