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

      systemd.services."usbip-bind@" = {
        description = "USB/IP daemon";
        wants = [ "network-online.target" "usbipd.service" ];
        after = [ "network-online.target" "usbipd.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cfg.package}/bin/usbip bind --busid %i";
          ExecStop = "${cfg.package}/bin/usbip unbind --busid %i";
          RemainAfterExit = true;
        };
      };
      systemd.services."usbip-bind@multi-user".enable = false;

      #      security.polkit.extraConfig = ''
      #        /* Log authorization checks. */
      #        polkit.addRule(function(action, subject) {
      #          polkit.log("user " +  subject.user + " is attempting action " + action.id + " from PID " + subject.pid);
      #        });
      #
      #        polkit.addRule(function(action, subject) {
      #            if (action.id == "org.debian.pcsc-lite.access_pcsc" ||
      #            action.id == "org.debian.pcsc-lite.access_card") {
      #            return polkit.Result.YES;
      #          }
      #        });
      #      '';
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
