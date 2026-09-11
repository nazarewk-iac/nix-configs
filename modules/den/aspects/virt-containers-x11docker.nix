# x11docker, as a den aspect. It ports
# `modules/universal/virtualisation/containers/x11docker/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs `x11docker` and every dependency the upstream table lists. x11docker runs a graphical
# program inside a container, on its own X server or Wayland compositor.
#
# ## One class only
#
# The old module runs on NixOS only, so this aspect serves the `nixos` class only.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B. The `apply` pipeline of that option becomes a `filterPackages` call, which matters
#    here: this list is long, and one entry can turn unavailable in a later nixpkgs.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-containers-x11docker.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      environment.systemPackages = filterPackages (
        with pkgs;
        [
          x11docker
          # x11docker deps, see https://github.com/mviereck/x11docker/wiki/dependencies#table-of-all-packages
          curl
          catatonit
          xorgserver # cvt
          dbus
          diffutils
          jq
          cups # lpstat
          perl
          pulseaudio
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
          wl-clipboard-x11
          xdg-utils
          xdotool
          xdpyinfo
          # Xephyr from xorg-server
          xinit
          # Xorg from xorg-server
          xpra
          xrandr
          # Xvfb from xorg-server
          xwininfo
        ]
      );
    };
}
