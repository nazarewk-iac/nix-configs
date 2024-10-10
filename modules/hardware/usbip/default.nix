{ lib, pkgs, config, ... }:
let
  # https://wiki.archlinux.org/title/USB/IP
  cfg = config.kdn.hardware.usbip;

  target = "network";
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
        after = [ "${target}.target" ];
        wantedBy = [ "${target}.target" ];

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/usbipd --tcp-port=${toString cfg.bindPort}";
        };
      };

      systemd.services."usbip-bind@" = {
        description = "USB/IP daemon";
        requires = [ "usbipd.target" ];
        after = [ "usbipd.service" "${target}.target" ];
        wantedBy = [ "${target}.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${cfg.package}/bin/usbip bind --busid %i";
          ExecStop = "${cfg.package}/bin/usbip unbind --busid %i";
        };
      };
      systemd.services."usbip-bind@${target}".enable = false;
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
