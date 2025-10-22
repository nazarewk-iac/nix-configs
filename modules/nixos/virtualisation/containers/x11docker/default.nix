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
      xorg.xorgserver # cvt
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
      xorg.setxkbmap
      socat
      gnutar
      unzip
      libva-utils # vainfo
      weston
      wmctrl
      wget
      xorg.xauth
      xbindkeys
      #xclip
      wl-clipboard-x11
      xdg-utils
      xdotool
      xorg.xdpyinfo
      # Xephyr from xorg-server
      # xfishtank unavailablr
      xorg.xinit
      # Xorg from xorg-server
      xpra
      xorg.xrandr
      # Xvfb from xorg-server
      xorg.xwininfo
    ];
  };
}
