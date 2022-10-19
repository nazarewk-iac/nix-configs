{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.sway.base;

  mod = import ./_modifiers.nix;
in
{
  options.kdn.sway.base = {
    enable = lib.mkEnableOption "Sway base setup";
  };

  imports = [
    ./media-keys.nix
    ./notifications.nix
    ./swaylock.nix
    ./swayr.nix
    ./waybar.nix
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
      config.keybindings =
        let
          exec = cmd: "exec '${cmd}'";
        in
        {
          # X parity
          "${mod.lalt}+F4" = "kill";
          "${mod.super}+E" = exec "thunar"; # fix using it by nix path
          # Scratchpad:
          #   Sway has a "scratchpad", which is a bag of holding for windows.
          #   You can send windows there and get them back later.
          # Move the currently focused window to the scratchpad
          #"$Super+Shift+minus" = "move scratchpad";
          # Show the next scratchpad window or hide the focused scratchpad window.
          # If there are multiple scratchpad windows, this command cycles through them.
          #"$Super+minus" = "scratchpad show";
        };
      config.modes = { };
      config.bars = [ ];
      config.focus.followMouse = false;
      config.floating.modifier = mod.super;
      config.workspaceLayout = "tabbed";
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
