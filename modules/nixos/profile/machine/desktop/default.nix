{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.desktop;
in {
  options.kdn.profile.machine.desktop = {
    enable = lib.mkEnableOption "enable desktop machine profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.profile.machine.desktop.enable = cfg.enable;}];}
    {
      kdn.desktop.base.enable = true;
      kdn.hw.gpu.enable = true;
      kdn.hw.qmk.enable = true;
      kdn.profile.machine.basic.enable = true;

      # INPUT
      services.xserver.xkb.layout = "pl";
      console.useXkbConfig = true;
      services.libinput.enable = true;
      services.libinput.touchpad.disableWhileTyping = true;
      services.libinput.touchpad.naturalScrolling = true;
      services.libinput.touchpad.tapping = true;
      services.xserver.synaptics.twoFingerScroll = true;

      kdn.hw.audio.enable = true;

      kdn.desktop.enable = true;

      boot.extraModulePackages = with config.boot.kernelPackages; [v4l2loopback];

      kdn.services.printing.enable = true;
      kdn.programs.firefox.enable = true;
      kdn.programs.kdeconnect.enable = true;
      environment.systemPackages = with pkgs; [
        libreoffice-qt # non-qt failed to build on 2023-04-07
        # chromium
        thunderbird
        p7zip
        rar
        system-config-printer

        gparted
        gsmartcontrol
        smartmontools

        imagemagick

        playerctl
        pdftk

        (pkgs.writeScriptBin "qrpaste" ''
          #! ${pkgs.bash}/bin/bash
          ${pkgs.wl-clipboard}/bin/wl-paste | ${pkgs.qrencode}/bin/qrencode -o - | ${pkgs.imagemagick}/bin/display
        '')
        (pkgs.writeScriptBin "qrdecode" ''
          #! ${pkgs.bash}/bin/bash
          set -xeEuo pipefail
          export PATH="${lib.makeBinPath (with pkgs; [wl-clipboard coreutils zbar gnugrep libnotify])}:$PATH"

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
        '')
      ];
    }
  ]);
}
