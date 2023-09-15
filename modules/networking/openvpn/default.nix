{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.openvpn;
in
{
  options.kdn.networking.openvpn = {
    enable = lib.mkEnableOption "OpenVPN setup wrapper";
    instances = lib.mkOption {
      type = with lib.types; attrsOf (submodule {
        options = {
          config = lib.mkOption {
            type = types.lines;
            default = "";
          };
          ignoreRoutes = lib.mkOption {
            type = types.bool;
            default = false;
          };
        };
      });
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.openvpn.servers = lib.attrsets.mapAttrs
      (instance: extra: {
        config = ''
          config /etc/kdn/openvpn/${instance}/config.ovpn
          ${lib.optionalString extra.ignoreRoutes "pull-filter ignore redirect-gateway"}
          ${extra.config}
        '';
        autoStart = lib.mkDefault false;
      })
      cfg.instances;
    systemd.services = lib.attrsets.mapAttrs'
      (instance: extra: lib.nameValuePair "openvpn-${instance}" {
        serviceConfig.WorkingDirectory = "/etc/kdn/openvpn/${instance}";
      })
      cfg.instances;

    environment.systemPackages = [
      (lib.kdn.shell.writeShellScript pkgs ./bin/kdn-openvpn-setup.sh {
        runtimeInputs = with pkgs; [ xkcdpass ];
      })
    ];
  };
}
