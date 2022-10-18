{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.sway.base;
in
{
  options.kdn.sway.base = {
    enable = lib.mkEnableOption "Sway base setup";
  };

  imports = [
    ./waybar.nix
    ./swaylock.nix
  ];

  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    services.blueman-applet.enable = true;
    services.network-manager-applet.enable = true;

    services.flameshot.enable = true;
    services.flameshot.settings = {
      General = {
        checkForUpdates = false;
        contrastOpacity = 188;
        copyPathAfterSave = false;
        drawColor = "#ffff00";
        filenamePattern = "screenshot-%F_%T";
        saveAfterCopy = true;
        saveAsFileExtension = "jpg";
        savePathFixed = true;
        showStartupLaunchMessage = false;
        uploadHistoryMax = 25;
        useJpgForClipboard = true;
      };
    };

    wayland.windowManager.sway = {
      enable = true;
      config.keybindings = { };
      config.modes = { };
      config.bars = [ ];
      config.focus.followMouse = false;
      extraConfig = builtins.readFile ./sway/config;
    };

    xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;
    xdg.configFile."wofi/config".source = ./wofi/config;

    programs.foot = {
      enable = true;
      server.enable = false;
      settings = {
        main = {
          font = "JetBrainsMono Nerd Font Mono:style=Regular:size=12";
          dpi-aware = "yes";
        };
      };
    };
  };
}
