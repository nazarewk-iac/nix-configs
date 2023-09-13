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
      type = with lib.types; attrsOf attrs;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    services.openvpn.servers = lib.attrsets.mapAttrs
      (instance: extra: {
        config = "config /etc/kdn/openvpn/${instance}/config.ovpn";
        autoStart = lib.mkDefault false;
      })
      cfg.instances;

    environment.systemPackages = [
      (lib.kdn.shell.writeShellScript pkgs ./bin/kdn-openvpn-setup.sh {
        runtimeInputs = with pkgs; [ xkcdpass ];
      })
    ];
  };
}
