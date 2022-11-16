{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.networking.netbird;
in
{
  options.kdn.networking.netbird = {
    enable = lib.mkEnableOption "Netbird VPN based on Wireguard";
  };

  config = lib.mkIf cfg.enable {
    services.netbird.enable = true;

    networking.networkmanager.unmanaged = [ "interface-name:wt*" ];
    systemd.services.netbird = {
      serviceConfig = {
        Environment = [
          "NB_LOG_LEVEL=debug"
        ];
      };
    };
    environment.systemPackages = with pkgs; [
      netbird-ui
    ];
  };
}
