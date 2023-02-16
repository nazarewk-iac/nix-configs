{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.gaming;
in
{
  options.kdn.profile.machine.gaming = {
    enable = lib.mkEnableOption "enable gaming machine profile";
  };

  config = lib.mkIf cfg.enable {
    # see https://nixos.wiki/wiki/Steam
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    };
    environment.systemPackages = with pkgs; [
      # steam  # both covered by programs.steam.enable
      # steam-run
      steamcmd
      steam-tui
      steamPackages.steam-runtime
    ];
  };
}
