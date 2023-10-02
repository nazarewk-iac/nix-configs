{ lib
, pkgs
, config
, ...
}:
let
  cfg = config.kdn.networking.openfortivpn;
in
{
  options.kdn.networking.openfortivpn = {
    enable = lib.mkEnableOption "openfortivpn setup";
  };

  config = lib.mkIf cfg.enable {
    # see https://github.com/NixOS/nixpkgs/issues/231038#issuecomment-1637903456
    # see https://github.com/adrienverge/openfortivpn/issues/920
    environment.etc."ppp/options".text = "ipcp-accept-remote";
    environment.systemPackages = with pkgs; [
      openfortivpn
    ];
  };
}
