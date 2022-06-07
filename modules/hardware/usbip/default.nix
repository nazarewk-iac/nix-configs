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

      package = mkOption {
        type = types.package;
        default = config.boot.kernelPackages.usbip;
      };

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

      environment.systemPackages = [
        cfg.package
      ];

      systemd.services.usbipd = {
        description = "USB/IP daemon";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/usbipd --tcp-port=${toString cfg.bindPort}";
        };
      };
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
