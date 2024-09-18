{ lib, pkgs, config, ... }:
let
  # https://wiki.archlinux.org/title/USB/IP
  cfg = config.kdn.hardware.usbip;
in
{
  options = {
    kdn.hardware.usbip = {
      enable = lib.mkEnableOption "USB/IP setup";

      package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.usbip;
      };

      bindInterface = lib.mkOption {
        type = lib.types.str;
        default = "wg0";
      };

      bindPort = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 3240;
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
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
        wants = [ "network.target" ];
        after = [ "network.target" ];
        wantedBy = [ "network.target" ];

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/usbipd --tcp-port=${toString cfg.bindPort}";
        };
      };

      systemd.services."usbip-bind@" = {
        description = "USB/IP daemon";
        wants = [ "network.target" "usbipd.service" ];
        after = [ "network.target" "usbipd.service" ];
        wantedBy = [ "network.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cfg.package}/bin/usbip bind --busid %i";
          ExecStop = "${cfg.package}/bin/usbip unbind --busid %i";
          RemainAfterExit = true;
        };
      };
      systemd.services."usbip-bind@multi-user".enable = false;
    }
    (lib.mkIf (cfg.bindInterface == "*") {
      networking.firewall.allowedTCPPorts = [
        cfg.bindPort
      ];
    })
    (lib.mkIf (cfg.bindInterface != "*") {
      networking.firewall.interfaces.${cfg.bindInterface}.allowedTCPPorts = [
        cfg.bindPort
      ];
    })
  ]);
}
