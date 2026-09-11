# Four small sway aspects, in one file. Each one ports one file of `desktop/sway/home-manager`:
#
#   * `desktop-sway-swaylock`    — the screen lock and the idle timer (`swaylock.nix`).
#   * `desktop-sway-media-keys`  — the volume, brightness, media and screenshot keys (`media-keys.nix`).
#   * `desktop-sway-swayr`       — the window switcher and its daemon (`swayr.nix`).
#   * `desktop-sway-swaync`      — the notification centre keybinding and its D-Bus service (`swaync/`).
#
# The old modules stay in place and keep working. This file is the parallel den implementation.
#
# ## Why one file for four aspects
#
# Each aspect is 20 to 40 lines, each one emits the `homeManager` class alone, and each one reads the
# same two shared values: the key-name map and the session environment target. So one file keeps the
# four side by side, and `../lib.nix` maps the four names to it. The same pattern serves the `fs-*`
# and the `toolset-*` names already.
#
# ## Class list: `homeManager`, four times
#
# Every option below is a Home Manager option, so each aspect holds one target.
#
# ## What the port changes, for all four
#
# 1. **Inclusion replaces the `enable` flag.** Each old module keys on the sway `enable` flag, and the
#    notification one keys on the swaync service flag. A den aspect has no `enable`.
# 2. **The unit target name comes from a shared option.** The old modules read a computed unit name out
#    of the sway option tree. ../common/desktop-sway.nix declares `kdn.desktop-sway.envsTarget` and
#    `kdn.desktop-sway.keys`, and both hold the same default as the old tree.
# 3. **A platform guard replaces the Home Manager guard.** Every program here is a Wayland program,
#    and Home Manager asserts that `systemd.user.*` needs Linux. Measured 2026-09-11.
# 4. **Two dead bindings go.** `swaylock.nix` binds the parent's own sway config and reads it nowhere,
#    and it opens a `with` over the key map that the body does not use. Measured 2026-09-11.
#
# ## Two deliberate additions
#
# An aspect stands alone, so it carries the files and the packages it needs:
#
#   * The swayr aspect writes `~/.config/swayr/config.toml` and installs the swayr package. The old
#     tree writes both from the sway module instead, two files away.
#   * The swaync aspect turns the swaync service on. The old tree relies on the nwg-shell module for
#     that, and it keeps only the two writes Home Manager misses. Two aspects that both set the flag
#     to `true` merge with no conflict.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
let
  swaylockHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      swayCfg = config.kdn.desktop-sway;
      lockCmd = "${pkgs.swaylock}/bin/swaylock -f";
      swaymsg = "${config.wayland.windowManager.sway.package}/bin/swaymsg";
    in
    {
      imports = [ ../common/desktop-sway.nix ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        wayland.windowManager.sway.config.keybindings = {
          "${swayCfg.keys.super}+L" = "exec ${lockCmd}";
        };

        services.swayidle.enable = true;
        services.swayidle.events."before-sleep" = lockCmd;
        services.swayidle.timeouts = [
          {
            timeout = 300;
            command = lockCmd;
          }
          {
            timeout = 240;
            command = ''${swaymsg} "output * dpms off"'';
            resumeCommand = ''${swaymsg} "output * dpms on"'';
          }
        ];

        systemd.user.services.swayidle.Unit.After = [ swayCfg.envsTarget ];
        systemd.user.services.swayidle.Unit.Requires = [ swayCfg.envsTarget ];

        programs.swaylock.enable = true;
        programs.swaylock.settings.show-failed-attempts = true;
      };
    };

  mediaKeysHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      swayCfg = config.kdn.desktop-sway;

      exec = cmd: "exec '${cmd}'";
      playerctl = lib.getExe pkgs.playerctl;
      volumectl = "${lib.getExe' pkgs.avizo "volumectl"} -d";
      lightctl = "${lib.getExe' pkgs.avizo "lightctl"} -d";
    in
    {
      imports = [ ../common/desktop-sway.nix ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        # avizo draws the volume and the brightness overlay.
        services.avizo.enable = true;
        services.avizo.settings = { };

        wayland.windowManager.sway.config.keybindings = {
          # Brightness
          "XF86MonBrightnessDown" = exec "${lightctl} down 2";
          "XF86MonBrightnessUp" = exec "${lightctl} up 2";
          # Volume
          "XF86AudioRaiseVolume" = exec "${volumectl} up 1";
          "XF86AudioLowerVolume" = exec "${volumectl} down 1";

          "XF86AudioMute" = exec "${volumectl} toggle-mute";
          "${swayCfg.keys.lalt}+XF86AudioMute" = exec "${volumectl} -m toggle-mute";
          "XF86AudioMicMute" = exec "${volumectl} -m toggle-mute";
          # Media controls
          # see https://www.reddit.com/r/swaywm/comments/ju1609/control_spotify_with_bluetooth_headset_with_dbus/
          "--locked XF86AudioPlay" = exec "${playerctl} play-pause";
          "--locked XF86AudioPause" = exec "${playerctl} play-pause";
          "--locked XF86AudioNext" = exec "${playerctl} next";
          "--locked XF86AudioPrev" = exec "${playerctl} previous";
          # Misc
          "Print" = exec "${lib.getExe config.services.flameshot.package} gui";
          "--inhibited Super+Print" = exec "${lib.getExe config.services.flameshot.package} gui";
        };
      };
    };

  swayrHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      swayCfg = config.kdn.desktop-sway;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      # Every swayr call goes through the journal, under its own identifier.
      systemd-cat = name: "${pkgs.systemd}/bin/systemd-cat --identifier=${config.home.username}-${name}";
      exec = cmd: "exec '${cmd}'";

      swayr = cmd: "${systemd-cat "swayr"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayr ${cmd}";
      swayrd = "${systemd-cat "swayrd"} env RUST_BACKTRACE=1 ${pkgs.swayr}/bin/swayrd";
    in
    {
      imports = [ ../common/desktop-sway.nix ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        home.packages = filterPackages [ pkgs.swayr ];
        xdg.configFile."swayr/config.toml".source = ./desktop-sway-small/swayr-config.toml;

        wayland.windowManager.sway.extraConfig = exec swayrd;
        wayland.windowManager.sway.config.keybindings = {
          "${swayCfg.keys.super}+Space" = exec (swayr "switch-window");
          "${swayCfg.keys.super}+Delete" = exec (swayr "quit-window");
          "${swayCfg.keys.super}+Tab" = exec (swayr "switch-to-urgent-or-lru-window");
          "${swayCfg.keys.lalt}+Tab" = exec (swayr "prev-window all-workspaces");
          "${swayCfg.keys.lalt}+${swayCfg.keys.shift}+Tab" = exec (swayr "next-window all-workspaces");
          "${swayCfg.keys.super}+${swayCfg.keys.shift}+Space" = exec (swayr "switch-workspace-or-window");
          "${swayCfg.keys.super}+C" = exec (swayr "execute-swaymsg-command");
          "${swayCfg.keys.super}+${swayCfg.keys.shift}+C" = exec (swayr "execute-swayr-command");
        };
      };
    };

  swayncHomeTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      swayCfg = config.kdn.desktop-sway;
      cfg = config.services.swaync;
    in
    {
      imports = [ ../common/desktop-sway.nix ];

      config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        # Home Manager runs the daemon, and it misses the two writes below.
        services.swaync.enable = true;

        xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source =
          "${cfg.package}/share/dbus-1/services/org.erikreider.swaync.service";

        wayland.windowManager.sway.config.keybindings = {
          "${swayCfg.keys.super}+N" = "exec ${lib.getExe' cfg.package "swaync-client"} -t -sw";
        };
      };
    };
in
{
  kdn.desktop-sway-swaylock.homeManager = swaylockHomeTarget;
  kdn.desktop-sway-media-keys.homeManager = mediaKeysHomeTarget;
  kdn.desktop-sway-swayr.homeManager = swayrHomeTarget;
  kdn.desktop-sway-swaync.homeManager = swayncHomeTarget;
}
