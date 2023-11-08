{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.desktop.sway;
  waybar = config.programs.waybar.package;

  settingsModules = {
    "sway/mode" = {
      "format" = " {}";
      "max-length" = 50;
    };
    "wlr/taskbar" = {
      "format" = "{icon}";
      "icon-size" = 15;
      "active-first" = false;
      "tooltip-format" = "{app_id}: {title}";
      "on-click" = "activate";
      "on-click-middle" = "close";
      "on-click-right" = "minimize-raise";
    };
    "keyboard-state" = {
      "numlock" = true;
      "capslock" = true;
      "format" = "{name} {icon}";
      "format-icons" = {
        "locked" = "";
        "unlocked" = "";
      };
    };
    "mpd" = {
      "format" = "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
      "format-disconnected" = "Disconnected ";
      "format-stopped" = "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
      "unknown-tag" = "N/A";
      "interval" = 2;
      "consume-icons" = {
        "on" = " ";
      };
      "random-icons" = {
        "off" = "<span color=\"#f53c3c\"></span> ";
        "on" = " ";
      };
      "repeat-icons" = {
        "on" = " ";
      };
      "single-icons" = {
        "on" = "1 ";
      };
      "state-icons" = {
        "paused" = "";
        "playing" = "";
      };
      "tooltip-format" = "MPD (connected)";
      "tooltip-format-disconnected" = "MPD (disconnected)";
    };
    "idle_inhibitor" = {
      "format" = "{icon}";
      "format-icons" = {
        "activated" = "";
        "deactivated" = "";
      };
    };
    "tray" = {
      "spacing" = 10;
      "show-passive-items" = true;
    };
    "clock" = {
      "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      "interval" = 1;
      "format" = "{:%H:%M:%S}";
      "format-alt" = "{:%Y-%m-%d %H:%M}";
      "on-scroll-up" = "gsimplecal prev_month";
      "on-scroll-down" = "gsimplecal next_month";
    };
    "cpu" = {
      "format" = "{usage}% ";
      "tooltip" = true;
    };
    "memory" = {
      "format" = "{}% ";
    };
    "temperature" = {
      # "thermal-zone" = 2;
      # "hwmon-path" = "/sys/class/hwmon/hwmon2/temp1_input";
      "critical-threshold" = 80;
      # "format-critical" = "{temperatureC}°C {icon}";
      "format" = "{temperatureC}°C {icon}";
      "format-icons" = [ "" "" "" ];
    };
    "backlight" = {
      # "device" = "acpi_video1";
      "format" = "{percent}% {icon}";
      "format-icons" = [ "" "" ];
    };
    "battery" = {
      "states" = {
        # "good" = 95;
        "warning" = 30;
        "critical" = 15;
      };
      "format" = "{capacity}% {icon}";
      "format-charging" = "{capacity}% ";
      "format-plugged" = "{capacity}% ";
      "format-alt" = "{time} {icon}";
      # "format-good" = "", # An empty format will hide the module
      # "format-full" = "";
      "format-icons" = [ "" "" "" "" "" ];
    };
    "battery#bat2" = {
      "bat" = "BAT2";
    };
    "network" = {
      # "interface" = "wlp2*", # (Optional) To force the use of this interface
      "format-wifi" = "{essid} ({signalStrength}%) ";
      "format-ethernet" = "{ipaddr}/{cidr} ";
      "tooltip-format" = "{ifname} via {gwaddr} ";
      "format-linked" = "{ifname} (No IP) ";
      "format-disconnected" = "Disconnected ⚠";
      "format-alt" = "{ifname}: {ipaddr}/{cidr}";
    };
    "pulseaudio" = {
      # "scroll-step" = 1, # %, can be a float
      "format" = "{volume}% {icon} {format_source}";
      "format-bluetooth" = "{volume}% {icon} {format_source}";
      "format-bluetooth-muted" = " {icon} {format_source}";
      "format-muted" = " {format_source}";
      "format-source" = "{volume}% ";
      "format-source-muted" = "";
      "format-icons" = {
        "headphone" = "";
        "hands-free" = "";
        "headset" = "";
        "phone" = "";
        "portable" = "";
        "car" = "";
        "default" = [ "" "" "" ];
      };
      "on-click" = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
      "on-click-middle" = "pavucontrol";
      "on-click-right" = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
    };
  };

  settings = {
    layer = "top";
    position = "top";
    height = 30;
    spacing = 4;
    modules-left = [ "sway/workspaces" "sway/mode" "custom/media" "wlr/taskbar" ];
    modules-center = [ "sway/window" ];
    modules-right = [
      # "mpd"
      "idle_inhibitor"
      "pulseaudio"
      # "network"
      "cpu"
      "memory"
      "temperature"
      "backlight"
      # "keyboard-state"
      "sway/language"
      "battery"
      "battery#bat2"
      "tray"
      "clock"
    ];
  };
in
{
  config = lib.mkIf (config.kdn.headless.enableGUI && cfg.enable) {
    xdg.configFile."waybar/config" = {
      source = (pkgs.formats.json { }).generate "waybar-config.json" (settings // settingsModules);
      onChange = ''
        ${pkgs.procps}/bin/pkill -u $USER -USR2 waybar || true
      '';
    };

    home.packages = with pkgs; [
      libappindicator
      libappindicator-gtk3
    ];

    systemd.user.services.waybar.Unit.BindsTo = [ "tray.target" ];
    systemd.user.services.waybar.Unit.Requires = [ config.kdn.desktop.sway.systemd.envs.target ];
    systemd.user.services.waybar.Unit.After = [ config.kdn.desktop.sway.systemd.envs.target ];
    systemd.user.services.waybar.Service.ExecStartPost = [ "${pkgs.coreutils}/bin/sleep 3" ];

    programs.waybar = {
      enable = true;
      systemd.enable = true;
      style = ./waybar/style.css;
      # TODO: resolve error and move from xdg.configFile."waybar/config":
      #  A definition for option `home-manager.users.kdn.programs.waybar.settings.height' is not of type `JSON value'. Definition values: 30
      # settings = settings // { modules = settingsModules; };
    };
  };
}
