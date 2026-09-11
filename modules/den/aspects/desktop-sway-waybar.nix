# waybar, the sway status bar, as a den aspect. It ports `desktop/sway/home-manager/waybar.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns on waybar as a systemd user service, and it writes one JSON configuration file: the bar
# geometry, three module lists, and the settings of every module in those lists.
#
# ## Class list: `homeManager`
#
# waybar runs as a user service, and `programs.waybar` is a Home Manager option. So this aspect holds
# one target, and it declares its options inside that target.
#
# ## The configuration file, and why it is not `programs.waybar.settings`
#
# Home Manager types `programs.waybar.settings` as a JSON value, and it rejects the `height` entry
# with "not of type `JSON value`". So this aspect writes `xdg.configFile."waybar/config"` itself, as
# the old module does. The `onChange` hook sends `SIGUSR2` to a running waybar, so a switch reloads
# the bar with no restart.
#
# ## What the port changes
#
# 1. **Inclusion replaces the `enable` flag.** The old module keys on the sway `enable` flag. A den
#    aspect has no `enable`, so the aspect list carries the choice.
# 2. **One dead `let` binding goes.** The old file binds `waybar = config.programs.waybar.package`
#    and reads it nowhere. Measured 2026-09-11 by a read of all 235 lines.
# 3. **The native option replaces the cross-platform package list.** The two tray libraries go to
#    `home.packages`, through ../common/filter-packages.nix.
# 4. **The unit target name comes from a shared option.** The old module reads a computed unit name
#    out of the sway option tree. ../common/desktop-sway.nix declares `kdn.desktop-sway.envsTarget`,
#    and it holds the same default name.
# 5. **A platform guard replaces the Home Manager guard.** waybar, avizo and the two tray libraries
#    are Linux-only, and Home Manager asserts that `systemd.user.*` needs Linux. Measured 2026-09-11.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  # The bar geometry and the three module lists. A commented entry names a module this bar does not
  # show today, and the port keeps every one of them.
  settings = {
    layer = "top";
    position = "top";
    height = 36;
    spacing = 4;
    modules-left = [
      "sway/workspaces"
      "sway/mode"
      "custom/media"
      "wlr/taskbar"
    ];
    modules-center = [
      "sway/window"
    ];
    modules-right = [
      # "mpd"
      "idle_inhibitor"
      "pulseaudio"
      # "network"
      "cpu"
      "memory"
      "temperature"
      "backlight"
      #"keyboard-state"
      "sway/language"
      "battery"
      "battery#bat2"
      "tray"
      "clock"
    ];
  };

  # The settings of every waybar module. It takes `lib` and `pkgs`, because the audio module calls a
  # volume program. So an unused read forces no package.
  settingsModules =
    { lib, pkgs }:
    {
      "sway/mode" = {
        "format" = " {}";
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
          "locked" = "";
          "unlocked" = "";
        };
      };
      "mpd" = {
        "format" =
          "{stateIcon} {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}{artist} - {album} - {title} ({elapsedTime:%M:%S}/{totalTime:%M:%S}) ⸨{songPosition}|{queueLength}⸩ {volume}% ";
        "format-disconnected" = "Disconnected ";
        "format-stopped" = "{consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped ";
        "unknown-tag" = "N/A";
        "interval" = 2;
        "consume-icons" = {
          "on" = " ";
        };
        "random-icons" = {
          "off" = "<span color=\"#f53c3c\"></span> ";
          "on" = " ";
        };
        "repeat-icons" = {
          "on" = " ";
        };
        "single-icons" = {
          "on" = "1 ";
        };
        "state-icons" = {
          "paused" = "";
          "playing" = "";
        };
        "tooltip-format" = "MPD (connected)";
        "tooltip-format-disconnected" = "MPD (disconnected)";
      };
      "idle_inhibitor" = {
        "format" = "{icon}";
        "format-icons" = {
          "activated" = "";
          "deactivated" = "";
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
        "format" = "{usage}% ";
        "tooltip" = true;
      };
      "memory" = {
        "format" = "{}% ";
      };
      "temperature" = {
        # "thermal-zone" = 2;
        # "hwmon-path" = "/sys/class/hwmon/hwmon2/temp1_input";
        "critical-threshold" = 80;
        # "format-critical" = "{temperatureC}°C {icon}";
        "format" = "{temperatureC}°C {icon}";
        "format-icons" = [
          ""
          ""
          ""
        ];
      };
      "backlight" = {
        # "device" = "acpi_video1";
        "format" = "{percent}% {icon}";
        "format-icons" = [
          ""
          ""
        ];
      };
      "battery" = {
        "states" = {
          # "good" = 95;
          "warning" = 30;
          "critical" = 15;
        };
        "format" = "{capacity}% {icon}";
        "format-charging" = "{capacity}% ";
        "format-plugged" = "{capacity}% ";
        "format-alt" = "{time} {icon}";
        # "format-good" = "", # An empty format will hide the module
        # "format-full" = "";
        "format-icons" = [
          ""
          ""
          ""
          ""
          ""
        ];
      };
      "battery#bat2" = {
        "bat" = "BAT2";
      };
      "network" = {
        # "interface" = "wlp2*", # (Optional) To force the use of this interface
        "format-wifi" = "{essid} ({signalStrength}%) ";
        "format-ethernet" = "{ipaddr}/{cidr} ";
        "tooltip-format" = "{ifname} via {gwaddr} ";
        "format-linked" = "{ifname} (No IP) ";
        "format-disconnected" = "Disconnected ⚠";
        "format-alt" = "{ifname}: {ipaddr}/{cidr}";
      };
      "pulseaudio" = {
        # "scroll-step" = 1, # %, can be a float
        "format" = "{volume}% {icon} {format_source}";
        "format-bluetooth" = "{volume}% {icon} {format_source}";
        "format-bluetooth-muted" = "🔇 {icon} {format_source}";
        "format-muted" = "🔇 {format_source}";
        "format-source" = "{volume}% ";
        "format-source-muted" = "";
        "format-icons" = {
          "default" = [
            ""
            ""
            ""
          ];

          # see https://github.com/Alexays/Waybar/blob/f5370fcff585419dcce67712b561217d33e8b65e/src/modules/pulseaudio.cpp#L40-L42
          "car" = "";
          "hands-free" = "";
          "hdmi" = "🖵";
          "headphone" = "";
          "headset" = "";
          "hifi" = "📻";
          "phone" = "";
          "portable" = "";
          "speaker" = "";
        };
        "on-click" = "${lib.getExe' pkgs.avizo "volumectl"} toggle-mute";
        "on-click-middle" = "pavucontrol";
        "on-click-right" = "${lib.getExe' pkgs.avizo "volumectl"} -m toggle-mute";
        "ignored-sinks" = [ "Easy Effects Sink" ];
      };
    };

  homeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.desktop-sway;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [ ../common/desktop-sway.nix ];

      # waybar is a Wayland program. See change 5 in the header.
      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        xdg.configFile."waybar/config" = {
          source = (pkgs.formats.json { }).generate "waybar-config.json" (
            settings // settingsModules { inherit lib pkgs; }
          );
          onChange = ''
            ${lib.getExe' pkgs.procps "pkill"} -u '${config.home.username}' -USR2 waybar || :
          '';
        };

        home.packages = filterPackages (
          with pkgs;
          [
            libappindicator
            libappindicator-gtk3
          ]
        );

        systemd.user.services.waybar.Unit.BindsTo = [ "tray.target" ];
        systemd.user.services.waybar.Unit.Requires = [ cfg.envsTarget ];
        systemd.user.services.waybar.Unit.After = [ cfg.envsTarget ];
        systemd.user.services.waybar.Service.ExecStartPost = [ "${pkgs.coreutils}/bin/sleep 3" ];

        programs.waybar.enable = true;
        programs.waybar.systemd.enable = true;
        # The settings stay in the file above. Home Manager rejects the `height` entry with:
        #   A definition for option `programs.waybar.settings.height' is not of type `JSON value'.
      };
    };
in
{
  kdn.desktop-sway-waybar.homeManager = homeTarget;
}
