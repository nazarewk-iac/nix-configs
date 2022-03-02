{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.discovery;
in {
  options.nazarewk.hardware.discovery = {
    enable = mkEnableOption "hardware discovery scripts";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (pkgs.writeShellApplication {
        name = "list-device-drivers";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          # shellcheck disable=SC2086
          ls -l /sys/class/''${1:-"*"}/''${2:-"*"}/device/driver
        '';
      })
      (pkgs.writeShellApplication {
        name = "find-device-kernel-module";
        runtimeInputs = with pkgs; [ pciutils gnugrep ];
        text = ''
          lspci -nn -k | grep -i -A"''${2:-3}" "$1" "''${@:3}"
        '';
      })
    ];
  };
}
