{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
  cfg = config.kdn.profile.machine.gaming;
in {
  options.kdn.profile.machine.gaming = {
    enable = lib.mkEnableOption "enable gaming machine profile";
    vulkan.deviceId = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    vulkan.deviceName = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    # see https://nixos.wiki/wiki/Steam
    programs.steam.enable = true;
    programs.steam.remotePlay.openFirewall = true;
    programs.steam.localNetworkGameTransfers.openFirewall = true;

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "steam"
        "steam-original"
        "steam-run"
      ];

    environment.sessionVariables =
      lib.optionalAttrs (cfg.vulkan.deviceName != null) {DXVK_FILTER_DEVICE_NAME = cfg.vulkan.deviceName;}
      // lib.optionalAttrs (cfg.vulkan.deviceId != null) {MESA_VK_DEVICE_SELECT = cfg.vulkan.deviceId;};

    environment.systemPackages = with pkgs; [
      # steam  # covered by programs.steam.enable
      # steam-run  # covered by programs.steam.enable
      steamcmd
      steam-tui

      # non-steam
      lutris
      heroic # A Native GOG, Epic, and Amazon Games Launcher for Linux, Windows and Mac

      # proton utils
      protonup-qt
      protonup-ng
      protontricks

      # wine utils
      winetricks
      bottles
      wine-wayland
    ];

    home-manager.sharedModules = [
      {
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
      }
    ];
  };
}
