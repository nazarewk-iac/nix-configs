{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.wg-0;
  hostname = config.networking.hostName;
in
{
  options.kdn.profile.host.wg-0 = {
    enable = lib.mkEnableOption "enable wg-0 host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.hetzner.enable = true;
      security.sudo.wheelNeedsPassword = false;
      services.netmaker.enable = true;
      services.netmaker.debugTools = true;
      services.netmaker.domain = "subsidize-stroller.kdn.im";
      services.netmaker.email = "subsidize-stroller@kdn.im";
      services.netmaker.coredns.defaults.bind = [ "ens3" ];

      environment.systemPackages = with pkgs; [
        sqlite
      ];
    }
  ]);
}
