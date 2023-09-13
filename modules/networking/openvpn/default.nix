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
    instances = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.trivial.pipe cfg.instances [
    (builtins.map (instance: {
      services.openvpn.servers."${instance}".config = "config /etc/kdn/openvpn/${instance}/config.ovpn";
    }))
    lib.mkMerge
  ];
}
