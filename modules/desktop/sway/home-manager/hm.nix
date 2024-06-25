{ osConfig, config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
  sysCfg = osConfig.kdn.desktop.sway;

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
  options.kdn.desktop.sway = {
    enable = lib.mkEnableOption "Sway base setup";
    prefix = lib.mkOption { type = with lib.types; str; };
    systemd = lib.mkOption { readOnly = true; };
    keys = lib.mkOption { readOnly = true; };
    launcher = lib.mkOption {
      type = with lib.types; listOf str;
    };
    fileManager = lib.mkOption {
      type = with lib.types; str;
      default = lib.getExe pkgs.cinnamon.nemo-with-extensions;
    };
  };

  imports = [
    ./media-keys.nix
    ./swaylock.nix
    ./swayr.nix
    ./waybar.nix
  ];

  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) (lib.mkMerge [
    {
      xsession.preferStatusNotifierItems = true;
      services.network-manager-applet.enable = true;
      systemd.user.services.network-manager-applet.Unit = {
        After = [ config.kdn.desktop.sway.systemd.envs.target ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
        Requires = lib.mkForce [ config.kdn.desktop.sway.systemd.envs.target ];
      };

      services.blueman-applet.enable = true;
      systemd.user.services.blueman-applet.Unit = {
        After = [ "tray.target" "bluetooth.target" config.kdn.desktop.sway.systemd.envs.target ];
        PartOf = [ config.kdn.desktop.sway.systemd.session.target ];
        Requires = lib.mkForce [ "tray.target" config.kdn.desktop.sway.systemd.envs.target ];
      };

      # segfaults https://github.com/NixOS/nixpkgs/issues/183730
      # cliboard not working https://github.com/NixOS/nixpkgs/issues/181759
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
        After = lib.mkForce [ "tray.target" config.kdn.desktop.sway.systemd.envs.target ];
        Requires = lib.mkForce [ "tray.target" config.kdn.desktop.sway.systemd.envs.target ];
      };

      #kdn.programs.ulauncher.enable = true;
      #systemd.user.services.ulauncher.Unit = {
      #  After = [ config.kdn.desktop.sway.systemd.envs.target ];
      #  Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
      #};

      wayland.windowManager.sway.enable = true;

      wayland.windowManager.sway.extraConfig = ''
        bindswitch --reload --locked lid:on output eDP-1 disable
        bindswitch --reload --locked lid:off output eDP-1 enable

        include /etc/sway/config.d/*
      '';
      wayland.windowManager.sway.config = {
        defaultWorkspace = "workspace number 1";
        keybindings =
          let
            exec = cmd:
              let
                cmdString = if builtins.typeOf cmd == "list" then lib.escapeShellArgs cmd else "'${cmd}'";
              in
              "exec ${cmdString}";
          in
          with cfg.keys; {
            "--release ${super}+V" = exec (lib.getExe ydotool-paste); # fix using it by nix path
            "--inhibited --release ${super}+${ctrl}+V" = exec (lib.getExe ydotool-paste); # fix using it by nix path
            # X parity
            "${lalt}+F4" = "kill";
            "${super}+E" = exec cfg.fileManager;
            # Scratchpad:
            #   Sway has a "scratchpad", which is a bag of holding for windows.
            #   You can send windows there and get them back later.
            # Move the currently focused window to the scratchpad
            #"$Super+Shift+minus" = "move scratchpad";
            # Show the next scratchpad window or hide the focused scratchpad window.
            # If there are multiple scratchpad windows, this command cycles through them.
            #"$Super+minus" = "scratchpad show";
            "${super}+K" = exec (lib.getExe pkgs.qalculate-qt);
            "${super}+P" = exec "${lib.getExe pkgs.foot} --title=ipython ipython";
            "${super}+Return" = exec "${lib.getExe pkgs.foot}";
            # Launchers
            "${super}+D" = exec cfg.launcher;
            "${lalt}+F2" = exec "${pkgs.wofi}/bin/wofi --show run";
            # Kill focused window
            "${super}+${shift}+Q" = "kill";

            # layout stuff
            # Switch the current container between different layout styles
            "${super}+${ctrl}+S" = "layout stacking";
            "${super}+${ctrl}+T" = "layout tabbed";
            "${super}+${ctrl}+E" = "layout toggle split";

            # Make the current focus fullscreen
            "${super}+F" = "fullscreen";
            # Toggle the current focus between tiling and floating mode
            "${super}+${shift}+F" = "floating toggle";
            "${super}+${shift}+S" = "sticky toggle";
            # moving around

            # mode switching
            "${super}+R" = "mode resize";
            "${super}+Pause" = "mode passthrough";
            "${super}+Scroll_Lock" = "mode passthrough";

            # moving around
            "${super}+A" = "focus parent";
            "${super}+Left" = "focus left";
            "${super}+Down" = "focus down";
            "${super}+Up" = "focus up";
            "${super}+Right" = "focus right";
            "--border --whole-window ${super}+${mouse-up}" = "focus right";
            "--border --whole-window ${super}+${mouse-down}" = "focus left";
            "--border --whole-window ${super}+${shift}+${mouse-up}" = "focus next sibling";
            "--border --whole-window ${super}+${shift}+${mouse-down}" = "focus prev sibling";

            "${super}+${shift}+Left" = "move left";
            "${super}+${shift}+Down" = "move down";
            "${super}+${shift}+Up" = "move up";
            "${super}+${shift}+Right" = "move right";

            # workspaces
            "${super}+1" = "workspace number 1";
            "${super}+2" = "workspace number 2";
            "${super}+3" = "workspace number 3";
            "${super}+4" = "workspace number 4";
            "${super}+5" = "workspace number 5";
            "${super}+6" = "workspace number 6";
            "${super}+7" = "workspace number 7";
            "${super}+8" = "workspace number 8";
            "${super}+9" = "workspace number 9";
            "${super}+0" = "workspace number 10";

            "${super}+${shift}+1" = "move container to workspace number 1";
            "${super}+${shift}+2" = "move container to workspace number 2";
            "${super}+${shift}+3" = "move container to workspace number 3";
            "${super}+${shift}+4" = "move container to workspace number 4";
            "${super}+${shift}+5" = "move container to workspace number 5";
            "${super}+${shift}+6" = "move container to workspace number 6";
            "${super}+${shift}+7" = "move container to workspace number 7";
            "${super}+${shift}+8" = "move container to workspace number 8";
            "${super}+${shift}+9" = "move container to workspace number 9";
            "${super}+${shift}+0" = "move container to workspace number 10";
          };

        modes.passthrough = with cfg.keys; {
          "${super}+Pause" = "mode default";
          "${super}+Scroll_Lock" = "mode default";
        };

        modes.resize = with cfg.keys; {
          "${super}+${ctrl}+Left" = "resize shrink width 1";
          "${super}+${ctrl}+Down" = "resize grow height 1";
          "${super}+${ctrl}+Up" = "resize shrink height 1";
          "${super}+${ctrl}+Right" = "resize grow width 1";

          "${ctrl}+Left" = "resize shrink width 5";
          "${ctrl}+Down" = "resize grow height 5";
          "${ctrl}+Up" = "resize shrink height 5";
          "${ctrl}+Right" = "resize grow width 5";

          "Left" = "resize shrink width 15";
          "Down" = "resize grow height 15";
          "Up" = "resize shrink height 15";
          "Right" = "resize grow width 15";

          "${lalt}+Left" = "resize shrink width 50";
          "${lalt}+Down" = "resize grow height 50";
          "${lalt}+Up" = "resize shrink height 50";
          "${lalt}+Right" = "resize grow width 50";

          "${super}+${lalt}+Left" = "resize shrink width 100";
          "${super}+${lalt}+Down" = "resize grow height 100";
          "${super}+${lalt}+Up" = "resize shrink height 100";
          "${super}+${lalt}+Right" = "resize grow width 100";

          # Return to default mode
          "Return" = "mode default";
          "Escape" = "mode default";
        };
        bars = [ ];
        focus.followMouse = false;
        floating.modifier = "${cfg.keys.super} normal";
        workspaceLayout = "tabbed";
        workspaceAutoBackAndForth = true;
        input."type:touchpad" = {
          tap = "enabled";
          natural_scroll = "enabled";
        };
        input."type:keyboard" = {
          xkb_layout = "pl";
          # https://major.io/2022/05/24/sway-reload-causes-a-firefox-crash/
          # xkb_numlock = "enable";
          repeat_delay = "333";
          repeat_rate = "50";
        };

        floating = {
          border = 0;
          criteria = [
            { app_id = "org.kde.polkit-kde-authentication-agent-1"; }
            { app_id = "pinentry-qt"; }
            { app_id = "firefox"; title = "Picture-in-Picture"; }
            { app_id = "firefox"; title = "Firefox — Sharing Indicator"; }
          ];
        };

        window.commands =
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
              {
                criteria = { title = "File Operation Progress"; };
                commands = centerModal;
              }
            ];
            expandEntry = entry: builtins.map
              (command: { inherit (entry) criteria; inherit command; })
              entry.commands;
          in
          lib.lists.flatten (builtins.map expandEntry entries);
      };

      xdg.configFile."swayr/config.toml".source = ./swayr/config.toml;

      home.packages = with pkgs; [
        ydotool-paste

        qalculate-qt
        libqalculate
      ];

      home.sessionPath = [ "$HOME/.local/bin" ];
    }
    (
      let nwg = config.services.nwg-shell; in lib.mkMerge [
        {
          services.nwg-shell.enable = true;
          services.nwg-shell.drawer.opts.fm = cfg.fileManager;
          kdn.desktop.sway.launcher = [ nwg.drawer.exec ];
          systemd.user.services.nwg-panel.Unit.BindsTo = [ "tray.target" ];
          systemd.user.services.nwg-panel.Unit.Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
          systemd.user.services.nwg-panel.Unit.After = [ config.kdn.desktop.sway.systemd.envs.target ];
        }
        {
          services.nwg-shell.panel.enable = false; # disable because it seems to often hang up
          services.nwg-shell.panel.config.panel-bottom.enable = false;
        }
      ]
    )
  ]);
}
