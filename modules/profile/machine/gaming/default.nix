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
    programs.steam.enable = true;
    programs.steam.remotePlay.openFirewall = true;
    programs.steam.localNetworkGameTransfers.openFirewall = true;

    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-run"
    ];
    environment.systemPackages = with pkgs; [
      # steam  # covered by programs.steam.enable
      # steam-run  # covered by programs.steam.enable
      steamcmd
      steam-tui

      # non-steam
      lutris

      # proton utils
      protonup-qt
      protonup-ng
      protontricks

      # wine utils
      winetricks
      bottles
      wine-wayland
    ];

    home-manager.sharedModules = [{
      home.persistence."usr/data".directories = [
        ".local/share/bottles"
        ".local/share/Steam"
        ".local/share/lutris"
      ];
      home.persistence."usr/cache".directories = [
        ".local/share/lutris/runtime"
        ".local/share/bottles/runners"
        ".local/share/bottles/temp"
        ".local/share/bottles/dxvk"
        ".local/share/Steam/steamapps"
      ];
    }];
  };
}
