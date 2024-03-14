{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.moss;
  hostname = config.networking.hostName;
in
{
  options.kdn.profile.host.moss = {
    enable = lib.mkEnableOption "enable moss host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.hetzner.enable = true;
      security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = with pkgs; [
        sqlite
      ];
    }
  ]);
}
