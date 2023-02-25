{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.containers.podman;
in
{
  options.kdn.containers.podman = {
    enable = lib.mkEnableOption "Podman setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      virtualisation.docker.enable = lib.mkDefault false;

      virtualisation.oci-containers.backend = "podman";
      virtualisation.podman.enable = true;
      virtualisation.podman.dockerCompat = !config.virtualisation.docker.enable;
      virtualisation.podman.dockerSocket.enable = !config.virtualisation.docker.enable;
      virtualisation.containers.containersConf.settings.storage.driver = "zfs";

      environment.systemPackages = with pkgs; [
        podman
        buildah
      ];
    }
    (lib.mkIf config.kdn.headless.enableGUI {
      environment.systemPackages = with pkgs; [
        x11docker
        # x11docker deps, see https://github.com/mviereck/x11docker/wiki/dependencies#table-of-all-packages
        curl
        catatonit
        xorg.xorgserver # cvt
        dbus
        diffutils
        jq
        # libsForQt5.kwin
        cups # lpstat
        perl
        podman
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
    })
  ]);
}
