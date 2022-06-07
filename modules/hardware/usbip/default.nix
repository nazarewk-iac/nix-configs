{ lib, pkgs, config, ... }:
with lib;
let
  # https://wiki.archlinux.org/title/USB/IP
  cfg = config.nazarewk.hardware.usbip;
in
{
  options = {
    nazarewk.hardware.usbip = {
      enable = mkEnableOption "USB/IP setup";

      bindInterface = mkOption {
        type = types.str;
        default = "wg0";
      };
      bindPort = mkOption {
        type = types.ints.unsigned;
        default = 3240;
      };
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
      boot.kernelModules = [
        "vhci-hcd"
        "usbip_host"
      ];

      environment.systemPackages = with pkgs; [
        config.boot.kernelPackages.usbip
      ];
    }
    (mkIf (cfg.bindInterface == "*") {
      networking.firewall.allowedTCPPorts = [
        cfg.bindPort
      ];
    })
    (mkIf (cfg.bindInterface != "*") {
      networking.firewall.interfaces.${cfg.bindInterface}.allowedTCPPorts = [
        cfg.bindPort
      ];
    })
  ]);
}
