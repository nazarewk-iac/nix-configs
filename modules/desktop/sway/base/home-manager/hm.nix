{ nixosConfig, config, pkgs, lib, ... }:
let
  sysCfg = nixosConfig.kdn.sway.base;

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

  config = lib.mkIf (config.kdn.headless.enableGUI && sysCfg.enable) {
    services.network-manager-applet.enable = true;

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

      config.floating = {
        border = 0;
        criteria = [
          { app_id = "org.kde.polkit-kde-authentication-agent-1"; }
          { app_id = "pinentry-qt"; }
          { app_id = "firefox"; title = "Picture-in-Picture"; }
          { app_id = "firefox"; title = "Firefox — Sharing Indicator"; }
        ];
      };

      config.window.commands =
        let
          modal = [
            "border none"
            "floating enable"
            "sticky enable"
          ];
          centerModal = modal ++ [
            "move position center"
          ];
          entries = [
            {
              criteria = { app_id = "firefox"; title = "Firefox — Sharing Indicator"; };
              commands = [ "resize set 10px 30px" ];
            }
          ];
          expandEntry = entry: builtins.map
            (command: { inherit (entry) criteria; inherit command; })
            entry.commands;
        in
        lib.lists.flatten (builtins.map expandEntry entries);
    };

    xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;
    xdg.configFile."wofi/config".source = ./wofi/config;

    home.packages = with pkgs; [
      # will override system-wide xdg-open
      (pkgs.writeShellApplication {
        name = "xdg-open";
        runtimeInputs = with pkgs; [ handlr ];
        text = ''handlr open "$@"'';
      })
    ];

    home.sessionPath = [ "$HOME/.local/bin" ];

    xdg.configFile."handlr/handlr.toml".source = (pkgs.formats.toml { }).generate "handlr.toml" {
      enable_selector = true;
      selector = "${pkgs.wofi}/bin/wofi -d -i -n --prompt='Open With: '";
    };

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
