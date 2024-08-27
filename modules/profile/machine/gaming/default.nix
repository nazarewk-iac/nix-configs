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
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "steam"
      "steam-original"
      "steam-run"
    ];
    environment.systemPackages = with pkgs; [
      # steam  # both covered by programs.steam.enable
      # steam-run
      steamcmd
      steam-tui
      steamPackages.steam-runtime

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
