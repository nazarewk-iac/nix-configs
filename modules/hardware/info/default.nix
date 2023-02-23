{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.info;
in
{
  options.kdn.hardware.info = {
    enable = lib.mkEnableOption "hardware discovery scripts";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dmidecode
      glxinfo
      hardinfo
      hddtemp
      hw-probe
      inxi
      lm_sensors
      lshw
      pciutils
      usbutils
      vulkan-caps-viewer

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
