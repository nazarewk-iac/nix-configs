# The `profile/machine/desktop` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# `profile-desktop` is the bundle for a machine with a screen. It reaches `profile-basic`, it names
# the desktop base, the three hardware aspects and the seven graphical programs, and it carries the
# input-device settings plus a set of graphical utilities.
#
# ## Class list: `nixos`, `darwin` and `homeManager`
#
# The old module holds its package list outside every context guard, so all three classes carry a
# package. The `nixos` class also carries libinput, the keyboard layout and `v4l2loopback`.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **The 13 `enable` writes become `includes` entries.**
# 3. **`kdn.desktop.enable` goes.** `modules/den/common/graphical.nix` declares the replacement
#    `kdn.graphical`, and `desktop-base` writes `lib.mkDefault true` into it. This bundle names
#    `desktop-base`, so the value arrives with no write from here.
# 4. **The `ifHMParent` forward goes.** `desktop/default.nix:31-33` forwards the profile into Home
#    Manager at plain priority, outside `mkIf cfg.enable`. The comment at `:17-30` explains why: the
#    whole old tree loads in the Home Manager context too, and the dev profile re-enabled the
#    desktop profile there. den has no such double load — an aspect resolves once per class — so
#    the whole hazard goes away and the forward is unnecessary.
# 5. **The keyboard layout read gets a fallback.** `desktop/default.nix:125` reads
#    `config.kdn.locale.xkbLayout`. `den-eval-instantiate` forces this pair alone, and the `locale`
#    aspect is then absent. `or "us"` keeps the pair resolvable, and `"us"` is the nixpkgs default
#    of `services.xserver.xkb.layout`, so nothing changes in a real consumer.
# 6. **`kdn.env.packages` goes.** Each target writes the native package option of its own class.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.**
# 2. **No reachable `enable` option.**
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  # The cross-platform part of the old package list.
  packages =
    pkgs: with pkgs; [
      imagemagick
      p7zip
      pdftk
      rar
      smartmontools
    ];

  # The Linux-only part. Two of the three are a small script over `wl-clipboard`.
  linuxPackages =
    pkgs:
    lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.playerctl
    ];

  lib = null; # placeholder, replaced below
in
{
  kdn.profile-desktop.includes = [
    kdn.desktop-base
    kdn.hw-audio
    kdn.hw-gpu
    kdn.hw-qmk
    kdn.profile-basic
    kdn.program-browsers-launcher
    kdn.program-chrome
    kdn.program-chromium
    kdn.program-firefox
    kdn.program-kdeconnect
    kdn.program-office
    kdn.program-thunderbird
    kdn.service-printing
  ];

  kdn.profile-desktop.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      services.xserver.xkb.layout = config.kdn.locale.xkbLayout or "us";
      console.useXkbConfig = lib.mkDefault true;
      services.libinput.enable = lib.mkDefault true;
      services.libinput.touchpad.disableWhileTyping = lib.mkDefault true;
      services.libinput.touchpad.naturalScrolling = lib.mkDefault true;
      services.libinput.touchpad.tapping = lib.mkDefault true;
      services.xserver.synaptics.twoFingerScroll = lib.mkDefault true;

      # A virtual camera, so a screen share reaches a video call.
      boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];

      environment.systemPackages = filterPackages (
        packages pkgs
        ++ (with pkgs; [
          gparted
          system-config-printer
          gsmartcontrol
          playerctl
          (pkgs.writeShellApplication {
            name = "qrpaste";
            runtimeInputs = with pkgs; [
              wl-clipboard
              qrencode
              imagemagick
            ];
            text = ''
              wl-paste | qrencode -o - | display
            '';
          })
          (pkgs.writeShellApplication {
            name = "qrdecode";
            runtimeInputs = with pkgs; [
              wl-clipboard
              coreutils
              zbar
              gnugrep
              libnotify
            ];
            text = ''
              src="''${1:-"''${src:-"clipboard"}"}"
              dst="''${2:-"''${dst:-"clipboard"}"}"

              case "$src" in
                clipboard)
                  type="$(wl-paste -l | grep 'image/' | head -n1)"
                  if test -z "$type" ; then
                    notify-send "qrdecode: error" "no image type amongst: $(printf "%s," $(wl-paste -l))"
                    exit 1
                  fi
                  output="$(wl-paste -t "$type" | zbarimg -1 -)"
                  echo "qrdecode: read from clipboard" >&2
                ;;
                -)
                  output="$(zbarimg -1 -)"
                  echo "qrdecode: read from stdin" >&2
                ;;
                *)
                  output="$(zbarimg -1 "$src")"
                  echo "qrdecode: read from $src" >&2
                ;;
              esac

              case "$dst" in
                clipboard)
                  echo -n "$output" | wl-copy
                  notify-send "qrdecode: success" "decoded to clipboard"
                ;;
                -)
                  printf "%s" "$output"
                  echo "qrdecode: decoded to stdout" >&2
                ;;
                *)
                  printf "%s" "$output" >"$dst"
                  echo "qrdecode: decoded to $dst" >&2
                ;;
              esac
            '';
          })
        ])
      );
    };

  kdn.profile-desktop.darwin =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = import ../common/filter-packages.nix { inherit lib; } (packages pkgs);
    };

  kdn.profile-desktop.homeManager =
    { lib, pkgs, ... }:
    {
      home.packages = import ../common/filter-packages.nix { inherit lib; } (packages pkgs);
    };
}
