{ nixosConfig, config, pkgs, lib, ... }:
let
  sysCfg = nixosConfig.kdn.sway.base;

  mod = import ./_modifiers.nix;
  ydotool-paste = pkgs.writeShellApplication {
    name = "ydotool-paste";
    runtimeInputs = with pkgs; [ ydotool wl-clipboard ];
    text = ''
      sleep "''${1:-0.5}"
      wl-paste --no-newline | ydotool type --file=-
    '';
  };
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
    services.clipman.enable = true; # wl-paste clipman
    services.clipman.systemdTarget = "tray.target";

    services.network-manager-applet.enable = false; # doesn't work/show up in tray
    systemd.user.services.network-manager-applet.Unit = {
      After = [ "tray.target" ];
      PartOf = [ "kdn-sway-session.target" ];
      Requisite = [ "tray.target" "kdn-sway-envs.target" ];
      Requires = lib.mkForce [ ];
    };


    services.blueman-applet.enable = true;
    systemd.user.services.blueman-applet.Unit = {
      After = [ "tray.target" ];
      PartOf = [ "kdn-sway-session.target" ];
      Requisite = [ "tray.target" "kdn-sway-envs.target" ];
      Requires = lib.mkForce [ ];
    };

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
    systemd.user.services.flameshot.Unit = {
      After = [ "tray.target" ];
      PartOf = [ "kdn-sway-session.target" ];
      Requisite = [ "tray.target" "kdn-sway-envs.target" ];
      Requires = lib.mkForce [ ];
    };

    wayland.windowManager.sway = {
      enable = true;
      config.keybindings =
        let
          exec = cmd: "exec '${cmd}'";
        in
        {
          "--release ${mod.super}+V" = exec "${ydotool-paste}/bin/ydotool-paste"; # fix using it by nix path
          "--inhibited --release ${mod.super}+${mod.ctrl}+V" = exec "${ydotool-paste}/bin/ydotool-paste"; # fix using it by nix path
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
        runtimeInputs = with pkgs; [ kdn.handlr-regex ];
        text = ''handlr open "$@"'';
      })
      ydotool-paste
    ];

    home.sessionPath = [ "$HOME/.local/bin" ];

    xdg.configFile."handlr/handlr.toml".source = (pkgs.formats.toml { }).generate "handlr.toml" {
      enable_selector = true;
      selector =
        let
          app = (pkgs.writeShellApplication {
            name = "handlr-selector";
            runtimeInputs = with pkgs; [ wofi ];
            text = ''
              cacheDir="$(mktemp -d -t handlr-selector.XXXX)"
              trap 'rm -rf $cacheDir || true' EXIT
              if wofi --dmenu --insensitive --normal-window --prompt='Open With: ' > "$cacheDir/stdout" ; then
                cat "$cacheDir/stdout"
              else
                exit 1
              fi
            '';
          });
        in
        "${app}/bin/handlr-selector";
    };

    programs.foot = {
      enable = true;
      server.enable = false;
      settings = {
        main = {
          font = "JetBrainsMono Nerd Font Mono:style=Regular:size=12";
          dpi-aware = "no";
        };
      };
    };
  };
}
