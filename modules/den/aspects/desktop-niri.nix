# The Niri session, generated from typed options. This is the evaluation PoC of
# `docs/tasks/2026-11/wayland-session-modernization/001-niri-composable-config`.
#
# ## What it does
#
# It declares one typed surface, `kdn.desktop-niri`, and renders it into
# `wayland.windowManager.niri.settings`. The build runs `niri validate` through
# `checkConfig`, so a wrong action name or a wrong KDL shape fails the build, not the session.
#
# ## Why the Sway tree stays untouched
#
# The task's hard constraint is coexistence: this aspect adds a second session and changes no
# Sway unit, environment, portal or default session. `programs.niri` is enabled, its desktop entry
# lands in the display manager, and `defaultSession` stays what it is.
#
# ## The Sway shortcut inventory is the input
#
# `defaultBindings` reproduces the catalog of
# `../../docs/tasks/2026-11/wayland-session-modernization/001-niri-composable-config/shortcuts.research.md`.
# Every entry names its Sway source. The nine `accepted-loss` rows (sticky, scratchpad,
# `layout stacking`, `focus parent`, the two sibling-focus wheel binds, and the two resize-mode
# exits) are absent by design; the user signed them off on 2026-11-16.
#
# ## Rendering rules (do not undo them)
#
# 1. `window-rule`, `output`, `workspace` and `spawn-at-startup` are **ordered lists**, rendered
#    through `_children`. An attribute set would lose the order and the repetition.
# 2. A bind is an attribute set keyed by its chord. Two definitions of one chord is a conflict, so
#    the aspect asserts uniqueness.
# 3. `extraKdl` is the escape hatch. Every use carries a comment naming the missing option.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** The aspect reads no `{ host, ... }`.
# 2. **No `enable` option.** Inclusion is the switch. `session` selects a session model, and it is
#    not an `enable`.
# 3. **No custom module argument.** Each target takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
let
  bindingType =
    { lib, ... }:
    {
      options = {
        chord = lib.mkOption {
          type = lib.types.str;
          description = "The Niri chord, for example `Mod+Return`.";
        };
        action = lib.mkOption {
          type = lib.types.str;
          description = "The Niri action name, for example `spawn`. `niri validate` catches a typo.";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Positional arguments of the action.";
        };
        allowWhenLocked = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Keep the bind active while the session is locked.";
        };
        allowInhibiting = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Let an inhibiting client swallow the bind.";
        };
        repeat = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Repeat the action while the chord is held.";
        };
        source = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "The Sway binding this row ports. Empty means a Niri-only addition.";
        };
        parity = lib.mkOption {
          type = lib.types.enum [ "reproduced" "alternative" "accepted-loss" ];
          default = "reproduced";
          description = "The parity state from `shortcuts.research.md`.";
        };
        note = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Why the row is an alternative or a loss.";
        };
      };
    };

  outputType =
    { lib, ... }:
    {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "The output name, for example `DP-1`.";
        };
        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
          description = "The KDL children of this `output` node.";
        };
      };
    };

  # The default catalog, a function of the key map. The user may replace the whole list.
  defaultBindings =
    k:
    let
      super = k.super;
      shift = k.shift;
      ctrl = k.ctrl;
      alt = k.alt;
    in
    [
      # --- core (shortcuts.research.md §1) ---------------------------------
      {
        chord = "${super}+V";
        action = "spawn";
        args = [ "ydotool-paste" ];
        repeat = false;
        source = "desktop/sway/home-manager/default.nix:127";
        parity = "alternative";
        note = "Sway uses a release bind; Niri has no release binds, so the press fires once.";
      }
      {
        chord = "${super}+${ctrl}+V";
        action = "spawn";
        args = [ "ydotool-paste" ];
        repeat = false;
        allowInhibiting = false;
        source = "desktop/sway/home-manager/default.nix:128";
        parity = "alternative";
      }
      {
        chord = "${alt}+F4";
        action = "close-window";
        source = "desktop/sway/home-manager/default.nix:131";
      }
      {
        chord = "${ctrl}+${alt}+${k.delete}";
        action = "spawn";
        args = [ "wlogout" ];
        source = "desktop/sway/home-manager/default.nix:133";
      }
      {
        chord = "${super}+E";
        action = "spawn";
        args = [ "nemo" ];
        source = "desktop/sway/home-manager/default.nix:134";
      }
      {
        chord = "${super}+K";
        action = "spawn";
        args = [ "qalculate-qt" ];
        source = "desktop/sway/home-manager/default.nix:142";
      }
      {
        chord = "${super}+Return";
        action = "spawn";
        args = [ "foot" ];
        source = "desktop/sway/home-manager/default.nix:143";
      }
      {
        chord = "${super}+D";
        action = "spawn";
        args = [ "nwg-drawer" ];
        source = "desktop/sway/home-manager/default.nix:144";
      }
      {
        chord = "${alt}+F2";
        action = "spawn";
        args = [ "wofi" "--show" "run" ];
        source = "desktop/sway/home-manager/default.nix:145";
      }
      {
        chord = "${super}+${shift}+Q";
        action = "close-window";
        source = "desktop/sway/home-manager/default.nix:147";
      }
      {
        chord = "${super}+${ctrl}+T";
        action = "toggle-column-tabbed-display";
        source = "desktop/sway/home-manager/default.nix:155";
        parity = "alternative";
      }
      {
        chord = "${super}+F";
        action = "fullscreen-window";
        source = "desktop/sway/home-manager/default.nix:160";
      }
      {
        chord = "${super}+${shift}+F";
        action = "toggle-window-floating";
        source = "desktop/sway/home-manager/default.nix:162";
      }
      {
        chord = "${super}+R";
        action = "switch-preset-column-width";
        source = "desktop/sway/home-manager/default.nix:166";
        parity = "alternative";
        note = "Sway enters a resize mode; Niri cycles the preset widths instead.";
      }
      {
        chord = "${super}+Pause";
        action = "toggle-keyboard-shortcuts-inhibit";
        source = "desktop/sway/home-manager/default.nix:167";
        parity = "alternative";
      }
      {
        chord = "${super}+Scroll_Lock";
        action = "toggle-keyboard-shortcuts-inhibit";
        source = "desktop/sway/home-manager/default.nix:168";
        parity = "alternative";
      }
      {
        chord = "${super}+Left";
        action = "focus-column-left";
        source = "desktop/sway/home-manager/default.nix:174";
      }
      {
        chord = "${super}+Down";
        action = "focus-window-down";
        source = "desktop/sway/home-manager/default.nix:175";
        parity = "alternative";
      }
      {
        chord = "${super}+Up";
        action = "focus-window-up";
        source = "desktop/sway/home-manager/default.nix:176";
        parity = "alternative";
      }
      {
        chord = "${super}+Right";
        action = "focus-column-right";
        source = "desktop/sway/home-manager/default.nix:177";
      }
      {
        chord = "${super}+${shift}+Left";
        action = "move-column-left";
        source = "desktop/sway/home-manager/default.nix:181";
      }
      {
        chord = "${super}+${shift}+Down";
        action = "move-window-down";
        source = "desktop/sway/home-manager/default.nix:182";
        parity = "alternative";
      }
      {
        chord = "${super}+${shift}+Up";
        action = "move-window-up";
        source = "desktop/sway/home-manager/default.nix:183";
        parity = "alternative";
      }
      {
        chord = "${super}+${shift}+Right";
        action = "move-column-right";
        source = "desktop/sway/home-manager/default.nix:184";
      }
      {
        chord = "${super}+${shift}+${ctrl}+Left";
        action = "move-workspace-to-monitor-left";
        source = "desktop/sway/home-manager/default.nix:186";
      }
      {
        chord = "${super}+${shift}+${ctrl}+Down";
        action = "move-workspace-to-monitor-down";
        source = "desktop/sway/home-manager/default.nix:187";
      }
      {
        chord = "${super}+${shift}+${ctrl}+Up";
        action = "move-workspace-to-monitor-up";
        source = "desktop/sway/home-manager/default.nix:188";
      }
      {
        chord = "${super}+${shift}+${ctrl}+Right";
        action = "move-workspace-to-monitor-right";
        source = "desktop/sway/home-manager/default.nix:189";
      }

      # --- workspaces 1..10 (shortcuts.research.md §1 rows 37-38) ----------
      {
        chord = "${super}+1";
        action = "focus-workspace";
        args = [ "1" ];
        source = "desktop/sway/home-manager/default.nix:192";
        parity = "alternative";
        note = "Sway uses numbered workspaces; Niri uses named workspaces.";
      }
      {
        chord = "${super}+2";
        action = "focus-workspace";
        args = [ "2" ];
        source = "desktop/sway/home-manager/default.nix:193";
        parity = "alternative";
      }
      {
        chord = "${super}+3";
        action = "focus-workspace";
        args = [ "3" ];
        source = "desktop/sway/home-manager/default.nix:194";
        parity = "alternative";
      }
      {
        chord = "${super}+4";
        action = "focus-workspace";
        args = [ "4" ];
        source = "desktop/sway/home-manager/default.nix:195";
        parity = "alternative";
      }
      {
        chord = "${super}+5";
        action = "focus-workspace";
        args = [ "5" ];
        source = "desktop/sway/home-manager/default.nix:196";
        parity = "alternative";
      }
      {
        chord = "${super}+6";
        action = "focus-workspace";
        args = [ "6" ];
        source = "desktop/sway/home-manager/default.nix:197";
        parity = "alternative";
      }
      {
        chord = "${super}+7";
        action = "focus-workspace";
        args = [ "7" ];
        source = "desktop/sway/home-manager/default.nix:198";
        parity = "alternative";
      }
      {
        chord = "${super}+8";
        action = "focus-workspace";
        args = [ "8" ];
        source = "desktop/sway/home-manager/default.nix:199";
        parity = "alternative";
      }
      {
        chord = "${super}+9";
        action = "focus-workspace";
        args = [ "9" ];
        source = "desktop/sway/home-manager/default.nix:200";
        parity = "alternative";
      }
      {
        chord = "${super}+0";
        action = "focus-workspace";
        args = [ "10" ];
        source = "desktop/sway/home-manager/default.nix:201";
        parity = "alternative";
      }
      {
        chord = "${super}+${shift}+1";
        action = "move-column-to-workspace";
        args = [ "1" ];
        source = "desktop/sway/home-manager/default.nix:203";
      }
      {
        chord = "${super}+${shift}+2";
        action = "move-column-to-workspace";
        args = [ "2" ];
        source = "desktop/sway/home-manager/default.nix:204";
      }
      {
        chord = "${super}+${shift}+3";
        action = "move-column-to-workspace";
        args = [ "3" ];
        source = "desktop/sway/home-manager/default.nix:205";
      }
      {
        chord = "${super}+${shift}+4";
        action = "move-column-to-workspace";
        args = [ "4" ];
        source = "desktop/sway/home-manager/default.nix:206";
      }
      {
        chord = "${super}+${shift}+5";
        action = "move-column-to-workspace";
        args = [ "5" ];
        source = "desktop/sway/home-manager/default.nix:207";
      }
      {
        chord = "${super}+${shift}+6";
        action = "move-column-to-workspace";
        args = [ "6" ];
        source = "desktop/sway/home-manager/default.nix:208";
      }
      {
        chord = "${super}+${shift}+7";
        action = "move-column-to-workspace";
        args = [ "7" ];
        source = "desktop/sway/home-manager/default.nix:209";
      }
      {
        chord = "${super}+${shift}+8";
        action = "move-column-to-workspace";
        args = [ "8" ];
        source = "desktop/sway/home-manager/default.nix:210";
      }
      {
        chord = "${super}+${shift}+9";
        action = "move-column-to-workspace";
        args = [ "9" ];
        source = "desktop/sway/home-manager/default.nix:211";
      }
      {
        chord = "${super}+${shift}+0";
        action = "move-column-to-workspace";
        args = [ "10" ];
        source = "desktop/sway/home-manager/default.nix:212";
      }

      # --- resize (shortcuts.research.md §2) ------------------------------
      {
        chord = "${super}+${ctrl}+Left";
        action = "set-column-width";
        args = [ "-1%" ];
        source = "desktop/sway/home-manager/default.nix:220";
        parity = "alternative";
      }
      {
        chord = "${super}+${ctrl}+Right";
        action = "set-column-width";
        args = [ "+1%" ];
        source = "desktop/sway/home-manager/default.nix:223";
        parity = "alternative";
      }
      {
        chord = "${super}+${ctrl}+Up";
        action = "set-window-height";
        args = [ "-1%" ];
        source = "desktop/sway/home-manager/default.nix:221";
        parity = "alternative";
      }
      {
        chord = "${super}+${ctrl}+Down";
        action = "set-window-height";
        args = [ "+1%" ];
        source = "desktop/sway/home-manager/default.nix:222";
        parity = "alternative";
      }
      {
        chord = "${alt}+Left";
        action = "switch-preset-column-width-back";
        source = "desktop/sway/home-manager/default.nix:232";
        parity = "alternative";
      }
      {
        chord = "${alt}+Right";
        action = "switch-preset-column-width";
        source = "desktop/sway/home-manager/default.nix:235";
        parity = "alternative";
      }
      {
        chord = "${super}+${alt}+Left";
        action = "maximize-column";
        source = "desktop/sway/home-manager/default.nix:238";
        parity = "alternative";
      }
      {
        chord = "${super}+${alt}+Right";
        action = "maximize-column";
        source = "desktop/sway/home-manager/default.nix:241";
        parity = "alternative";
      }

      # --- media keys (shortcuts.research.md §4) --------------------------
      {
        chord = "XF86MonBrightnessDown";
        action = "spawn";
        args = [ "lightctl" "down" "2" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86MonBrightnessUp";
        action = "spawn";
        args = [ "lightctl" "up" "2" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioRaiseVolume";
        action = "spawn";
        args = [ "volumectl" "up" "1" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioLowerVolume";
        action = "spawn";
        args = [ "volumectl" "down" "1" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioMute";
        action = "spawn";
        args = [ "volumectl" "toggle-mute" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "${alt}+XF86AudioMute";
        action = "spawn";
        args = [ "volumectl" "-m" "toggle-mute" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioMicMute";
        action = "spawn";
        args = [ "volumectl" "-m" "toggle-mute" ];
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioPlay";
        action = "spawn";
        args = [ "playerctl" "play-pause" ];
        allowWhenLocked = true;
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioPause";
        action = "spawn";
        args = [ "playerctl" "play-pause" ];
        allowWhenLocked = true;
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioNext";
        action = "spawn";
        args = [ "playerctl" "next" ];
        allowWhenLocked = true;
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "XF86AudioPrev";
        action = "spawn";
        args = [ "playerctl" "previous" ];
        allowWhenLocked = true;
        source = "desktop/sway/home-manager/media-keys.nix";
      }
      {
        chord = "Print";
        action = "spawn";
        args = [ "flameshot" "gui" ];
        source = "desktop/sway/home-manager/media-keys.nix";
        parity = "alternative";
      }
      {
        chord = "${super}+Print";
        action = "spawn";
        args = [ "flameshot" "gui" ];
        allowInhibiting = false;
        source = "desktop/sway/home-manager/media-keys.nix";
        parity = "alternative";
      }

      # --- application and session binds (§5) ----------------------------
      {
        chord = "${super}+L";
        action = "spawn";
        args = [ "swaylock" "-f" ];
        source = "desktop/sway/home-manager/swaylock.nix:25";
      }
      {
        chord = "${super}+N";
        action = "spawn";
        args = [ "swaync-client" "-t" "-sw" ];
        source = "desktop/sway/home-manager/swaync/default.nix:19";
      }
      {
        chord = "${super}+P";
        action = "spawn";
        args = [ "nwg-displays" ];
        source = "desktop/sway/home-manager/nwg-shell/default.nix:108";
      }
      {
        chord = "${super}+O";
        action = "spawn";
        args = [ "xdg-open-clipboard" ];
        source = "desktop/sway/home-manager/handlr/default.nix:75";
      }
      {
        chord = "${ctrl}+${super}+A";
        action = "spawn";
        args = [ "kdn-anonymize-clipboard" ];
        source = "desktop/sway/home-manager/default-secrets/default.nix:145";
      }

      # --- swayr family (§6) --------------------------------------------
      {
        chord = "${super}+Space";
        action = "focus-window-previous";
        source = "desktop/sway/home-manager/swayr.nix:25";
        parity = "alternative";
        note = "Swayr's switch-window becomes Niri's recent-windows.";
      }
      {
        chord = "${super}+${k.delete}";
        action = "close-window";
        source = "desktop/sway/home-manager/swayr.nix:26";
      }
      {
        chord = "${super}+Tab";
        action = "focus-window-previous";
        source = "desktop/sway/home-manager/swayr.nix:27";
        parity = "alternative";
      }
      {
        chord = "${alt}+Tab";
        action = "focus-window-previous";
        source = "desktop/sway/home-manager/swayr.nix:28";
        parity = "alternative";
      }
    ];

  declaration =
    { config, lib, ... }:
    {
      imports = [ ../common/desktop-niri.nix ];

      options.kdn.desktop-niri = {
        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "The Niri build. `null` keeps the nixpkgs default.";
        };
        bindings = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule bindingType);
          default = defaultBindings config.kdn.desktop-niri.keys;
          defaultText = "the Sway shortcut inventory";
          description = ''
            The bind catalog. The default reproduces the Sway shortcut inventory; a consumer may
            replace the whole list or append to it.
          '';
        };
        spawnAtStartup = lib.mkOption {
          type = lib.types.listOf (lib.types.listOf lib.types.str);
          default = [
            [ "waybar" ]
            [ "swaync" ]
            [ "kanshi" ]
          ];
          description = "Commands started with the session, in order. One list per command.";
        };
        windowRules = lib.mkOption {
          type = lib.types.listOf (lib.types.listOf lib.types.raw);
          default = [ ];
          description = "Ordered `window-rule` children. A list of lists, because order matters.";
        };
        outputs = lib.mkOption {
          type = lib.types.listOf (lib.types.submodule outputType);
          default = [ ];
          description = "Ordered `output` nodes.";
        };
        workspaces = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "1"
            "2"
            "3"
            "4"
            "5"
            "6"
            "7"
            "8"
            "9"
            "10"
          ];
          description = "Named workspaces, in order. The Sway ten workspaces become ten names.";
        };
        layout = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = {
            gaps = 4;
            center-focused-column = "never";
            default-column-width._children = [ { proportion = 0.5; } ];
            preset-column-widths._children = [
              { proportion = 0.33333; }
              { proportion = 0.5; }
              { proportion = 0.66667; }
            ];
          };
          description = "The `layout` node.";
        };
        input = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = {
            touchpad.tap = { };
            touchpad.natural-scroll = { };
            keyboard.xkb.layout = "pl";
          };
          description = "The `input` node.";
        };
        animations = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          default = { };
          description = "The `animations` node.";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            The `environment` node. It reaches only the processes Niri starts; it does not reach
            the systemd user manager. Do not export `GDK_BACKEND=wayland` here: it breaks the
            screencast portal.
          '';
        };
        session = lib.mkOption {
          type = lib.types.enum [ "niri-session" "niri-uwsm" ];
          default = "niri-session";
          description = "The session model. `niri-session` is the control of the UWSM A/B.";
        };
        useNautilus = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Use Nautilus as the portal's file chooser.";
        };
        portal.secret = lib.mkOption {
          type = lib.types.enum [ "gnome-keyring" "gtk" "none" ];
          default = "gnome-keyring";
          description = ''
            The `org.freedesktop.impl.portal.Secret` back-end. `none` leaves the interface to the
            bus name owner, which is how the repository's own `kdn-secret-service` serves it
            without starting a second keyring.
          '';
        };
        extraKdl = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Raw KDL appended after the generated file. The escape hatch.";
        };
        checkConfig = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run `niri validate` in the build.";
        };
      };
    };

  renderSettings =
    lib: cfg:
    let
      bindProps =
        b:
        (lib.optionalAttrs b.allowWhenLocked { "allow-when-locked" = true; })
        // (lib.optionalAttrs (!b.allowInhibiting) { "allow-inhibiting" = false; })
        // (lib.optionalAttrs (!b.repeat) { repeat = false; });

      renderBind =
        b:
        {
          name = b.chord;
          value = { "${b.action}" = if b.args == [ ] then { } else b.args; } // lib.optionalAttrs (bindProps b != { }) { _props = bindProps b; };
        };
    in
    {
      prefer-no-csd = { };
      input = cfg.input;
      layout = cfg.layout;
      animations = cfg.animations;
      environment = cfg.environment;
      binds = lib.listToAttrs (map renderBind cfg.bindings);
      _children =
        map (entry: { spawn-at-startup._args = entry; }) cfg.spawnAtStartup
        ++ map (name: { workspace._args = [ name ]; }) cfg.workspaces
        ++ map (out: { output._args = [ out.name ]; } // out.settings) cfg.outputs
        ++ map (rule: { window-rule._children = rule; }) cfg.windowRules;
    };
in
{
  kdn.desktop-niri.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = builtins.all (b: b.source != "") config.kdn.desktop-niri.bindings;
              message = "Every Niri bind must name its Sway source in `source`.";
            }
            {
              assertion =
                builtins.length (lib.unique (map (b: b.chord) config.kdn.desktop-niri.bindings))
                == builtins.length config.kdn.desktop-niri.bindings;
              message = "Two Niri binds share one chord; a chord is a conflict, not a merge.";
            }
          ];
        }
        {
          # Do NOT touch `displayManager.defaultSession`: Sway stays the default session.
          programs.niri = {
            enable = true;
            package = lib.mkDefault (if config.kdn.desktop-niri.package == null then pkgs.niri else config.kdn.desktop-niri.package);
            useNautilus = config.kdn.desktop-niri.useNautilus;
          };

          # `niri.service` binds to `graphical-session.target` but does not pull it here, so a
          # plain `niri-session` login starts no session services. Make the pull explicit; the
          # unit is ordered `Before` the target, so the bar and portals start after niri is up.
          systemd.user.services.niri.wants = [ "graphical-session.target" ];

          # The repository's own secret service claims `org.freedesktop.secrets`. The nixpkgs
          # module turns gnome-keyring on and points the portal's Secret interface at it; both
          # would fight the repo unit, so both are overridden.
          services.gnome.gnome-keyring.enable =
            lib.mkForce (config.kdn.desktop-niri.portal.secret == "gnome-keyring");
          xdg.portal.config.niri."org.freedesktop.impl.portal.Secret" =
            lib.mkDefault config.kdn.desktop-niri.portal.secret;

          # The Sway session's user units must not be pulled into a Niri session. This aspect
          # writes none of them; it only adds the Niri ones.
          environment.systemPackages = [ pkgs.xwayland-satellite ];
        }
        (lib.mkIf (config.kdn.desktop-niri.session == "niri-uwsm") {
          programs.uwsm = {
            enable = true;
            waylandCompositors.niri = {
              # The NixOS module appends " (UWSM)", so keep the bare name here.
              prettyName = "Niri";
              comment = "Niri managed by UWSM (A/B)";
              binPath = "/run/current-system/sw/bin/niri";
              # `wayland-wm@.service` is `Type=notify` and waits for `uwsm finalize`. Plain niri
              # never sends it, so the session target stays inactive and no service starts.
              # `--session` is niri's systemd mode: it imports the environment and notifies.
              extraArgs = [ "--session" ];
            };
          };
        })
      ];
    };

  kdn.desktop-niri.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ declaration ];

      config = {
        wayland.windowManager.niri = {
          enable = true;
          package = if config.kdn.desktop-niri.package == null then pkgs.niri else config.kdn.desktop-niri.package;
          checkConfig = config.kdn.desktop-niri.checkConfig;
          enableDefaultConfig = false;
          settings = renderSettings lib config.kdn.desktop-niri;
          extraConfig = config.kdn.desktop-niri.extraKdl;
        };
      };
    };
}
