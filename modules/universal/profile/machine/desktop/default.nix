{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.profile.machine.desktop;
in
{
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkMerge [
    # This forward sits OUTSIDE `lib.mkIf cfg.enable`, so a host that turns the profile off
    # also forwards that fact. The whole `modules/universal` tree loads in the home-manager
    # context too, so this module runs there and sets every `kdn.*` enable below. A host that
    # disables this profile, but keeps `kdn.profile.machine.dev`, re-enabled it inside
    # home-manager, because `profile/machine/dev/default.nix` sets
    # `kdn.profile.machine.desktop.enable = lib.mkDefault true`. The profile was then off in
    # the host and on in home-manager, and each enable below held two definitions with
    # different values. The evaluation stopped with `conflicting definition values`. Measured
    # 2026-09-10 on orr, for `kdn.desktop.enable` and `kdn.programs.browsers-launcher.enable`.
    #
    # The priority is plain (100), not `lib.mkDefault` (1000). A `lib.mkDefault` forward ties
    # with the `lib.mkDefault true` of the dev profile. Plain priority makes the host the
    # authority for this machine fact, which is correct -- a machine either has a desktop or
    # does not.
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.profile.machine.desktop = cfg; } ];
    })
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.desktop.base.enable = true;
          kdn.desktop.enable = true;
          kdn.hw.audio.enable = true;
          kdn.hw.gpu.enable = true;
          kdn.hw.qmk.enable = true;
          kdn.profile.machine.basic.enable = true;
          kdn.programs.browsers-launcher.enable = true;
          kdn.programs.chrome.enable = true;
          kdn.programs.chromium.enable = true;
          kdn.programs.firefox.enable = true;
          kdn.programs.kdeconnect.enable = true;
          kdn.programs.office.enable = true;
          kdn.programs.thunderbird.enable = true;
          kdn.services.printing.enable = true;

          kdn.env.packages = with pkgs; [
            imagemagick
            p7zip
            pdftk
            (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) playerctl)
            rar
            smartmontools

            (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) (
              pkgs.writeScriptBin "qrpaste" ''
                #! ${pkgs.bash}/bin/bash
                ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.qrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
              ''
            ))
            (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) (
              pkgs.writeScriptBin "qrdecode" ''
                #! ${pkgs.bash}/bin/bash
                set -xeEuo pipefail
                export PATH="${
                  lib.makeBinPath (
                    with pkgs;
                    [
                      wl-clipboard
                      coreutils
                      zbar
                      gnugrep
                      libnotify
                    ]
                  )
                }:$PATH"

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
                    print "%s" >"$dst"
                    echo "qrdecode: decoded to $dst" >&2
                  ;;
                esac
              ''
            ))
          ];
        }
        (kdnConfig.util.ifTypes [ "nixos" ] {
          services.xserver.xkb.layout = "pl";
          console.useXkbConfig = true;
          services.libinput.enable = true;
          services.libinput.touchpad.disableWhileTyping = true;
          services.libinput.touchpad.naturalScrolling = true;
          services.libinput.touchpad.tapping = true;
          services.xserver.synaptics.twoFingerScroll = true;

          boot.extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
          kdn.env.packages = with pkgs; [
            gparted
            system-config-printer
            gsmartcontrol
          ];
        })
      ]
    ))
  ];
}
