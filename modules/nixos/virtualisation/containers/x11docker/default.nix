{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualisation.containers.x11docker;
in {
  options.kdn.virtualisation.containers.x11docker = {
    enable = lib.mkEnableOption "x11docker setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      x11docker
      # x11docker deps, see https://github.com/mviereck/x11docker/wiki/dependencies#table-of-all-packages
      curl
      catatonit
      xorgserver # cvt
      dbus
      diffutils
      jq
      # kdePackages.kwin
      cups # lpstat
      perl
      # podman
      pulseaudio
      # python2
      python3
      setxkbmap
      socat
      gnutar
      unzip
      libva-utils # vainfo
      weston
      wmctrl
      wget
      xauth
      xbindkeys
      #xclip
      wl-clipboard-x11
      xdg-utils
      xdotool
      xdpyinfo
      # Xephyr from xorg-server
      # xfishtank unavailablr
      xinit
      # Xorg from xorg-server
      xpra
      xrandr
      # Xvfb from xorg-server
      xwininfo
    ];
  };
}
