{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  # https://wiki.archlinux.org/title/USB/IP
  cfg = config.kdn.hw.usbip;

  target = "network";
in
{
  options = {
    kdn.hw.usbip = {
      enable = lib.mkEnableOption "USB/IP setup";

      # TODO: research whether USB/IP is possible on Darwin
      package = lib.mkOption {
        type = lib.types.package;
        default =
          if kdnConfig.moduleType == "nixos" then config.boot.kernelPackages.usbip else pkgs.emptyFile;
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            kdn.env.packages = [
              cfg.package
            ];

            boot.kernelModules = [
              "vhci-hcd"
              "usbip_host"
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
              after = [
                "usbipd.service"
                "${target}.target"
              ];
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
        ]
      ))
    ]
  );
}
