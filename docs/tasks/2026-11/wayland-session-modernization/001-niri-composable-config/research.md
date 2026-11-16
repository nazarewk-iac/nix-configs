---
type: Research
description: Niri 26.04 module analysis, KDL composability, session and portal behaviour, and feature parity for the existing Sway workflow.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T17:10:00+01:00
---

# Niri research

Sources are the pinned store paths from [../research.md](../research.md) unless a URL says otherwise.

## 1. NixOS module `programs.niri`

File: `<nixpkgs>/nixos/modules/programs/wayland/niri.nix`. The module has three options:

| Option                      | Type and default     | Line     |
| --------------------------- | -------------------- | -------- |
| `programs.niri.enable`      | bool, `false`        | `:12`    |
| `programs.niri.package`     | package, `pkgs.niri` | `:14`    |
| `programs.niri.useNautilus` | bool, `true`         | `:16-18` |

What it writes:

| Effect                                                                                  | Line     |
| --------------------------------------------------------------------------------------- | -------- |
| `environment.systemPackages = [ cfg.package ]`                                          | `:24-26` |
| `services.dbus.packages = mkIf useNautilus [ pkgs.nautilus ]`                           | `:29-31` |
| `services.displayManager.sessionPackages = [ cfg.package ]`                             | `:34`    |
| `services.displayManager.defaultSession = lib.mkDefault "niri"`                         | `:42`    |
| `services.gnome.gnome-keyring.enable = lib.mkDefault true`                              | `:46`    |
| `systemd.packages = [ cfg.package ]`                                                    | `:49`    |
| `systemd.user.services.niri = { restartIfChanged = false; enableDefaultPath = false; }` | `:53-60` |
| `xdg.portal.enable = lib.mkDefault true`                                                | `:63`    |
| `xdg.portal.config.niri` with `gnome` and `gtk`, `Secret = gnome-keyring`               | `:66-75` |
| `xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ]`                           | `:79`    |
| imports `wayland-session.nix` with `enableWlrPortal = false`, `enableXWayland = false`  | `:83-87` |

The module does **not** install `xwayland-satellite`. A NixOS-only deployment must add
`pkgs.xwayland-satellite` to `environment.systemPackages` itself. The Home Manager module has an
`xwaylandSatellitePackage` option, so a Home Manager deployment can use that instead.

The module never mentions UWSM. `programs.uwsm` is an independent module.

## 2. Home Manager module `wayland.windowManager.niri`

File: `<home-manager>/modules/services/window-managers/niri.nix`.

| Option                     | Type and default                             | Line           |
| -------------------------- | -------------------------------------------- | -------------- |
| `enable`                   | bool, `false`                                | `:26`          |
| `package`                  | nullable package, `pkgs.niri`                | `:28-33`       |
| `systemd.enable`           | bool, `true`                                 | `:36-42`       |
| `systemd.variables`        | list of strings, `[]`; not used by niri      | `:45-53`       |
| `xwaylandSatellitePackage` | nullable package                             | `:56-63`       |
| `portalPackage`            | nullable package, `xdg-desktop-portal-gnome` | `:65-72`       |
| `checkConfig`              | bool, `package != null`                      | `:74-79`       |
| `settings`                 | `attrsOf valueType`                          | `:81-153`      |
| `enableDefaultConfig`      | bool, `false`                                | `:155`, `:211` |
| `extraConfig`              | lines, `""`                                  | `:157-172`     |

The `settings` value type is:

```nix
nullOr (oneOf [ bool int float str (attrsOf valueType) (listOf valueType) ])
```

It does **not** accept `lib.types.path`. Paths must be strings.

The module renders the file with:

```nix
toKDL = lib.hm.generators.toKDL {
  escapeBackslashes = true;
  escapeTabs = true;
};
settings = lib.removeSuffix "\n" (toKDL cfg.settings);
```

The order is: default config at `mkOrder 501`, settings at `mkOrder 999`.

`checkConfig` wraps the file in a derivation whose `checkPhase` runs `niri validate --config`. A bad
tree fails the build, not the login.

If `settings` is empty and `extraConfig` is empty, the module writes no file, and niri creates its
own mutable `~/.config/niri/config.kdl`.

The module does not use `wayland.systemd.target`. It installs the package's units through
`systemd.user.packages`, and the default `After=graphical-session.target` of the Home Manager
Wayland services is already correct because `niri.service` has `BindsTo=` and `Before=` that target.

## 3. The KDL generator

The generator is `<home-manager>/modules/lib/generators.nix:805-979`. Its contract:

| Nix shape              | KDL output                         |
| ---------------------- | ---------------------------------- |
| scalar                 | `attr <literal>`                   |
| empty attribute set    | bare `attr`                        |
| nested attribute set   | `attr { … }`                       |
| `_args = [ … ]`        | positional arguments               |
| `_props = { … }`       | `k=v` properties                   |
| `_children = [ … ]`    | ordered, repeatable children       |
| list of scalars        | `attr a b c`                       |
| list of attribute sets | `attr { - … }`, which niri rejects |
| anything else          | `throw "Cannot convert type …"`    |

Plain attributes are emitted in alphabetical order. This is harmless for most sections and wrong for
window rules, whose order is semantic.

Floats go through `toString`, so `0.5` becomes `0.500000`. This is valid KDL, only ugly.

## 4. What composition can and cannot express

| Need                                         | Expressible in `settings`    | How                                                         |
| -------------------------------------------- | ---------------------------- | ----------------------------------------------------------- |
| keybindings from the shared map              | yes                          | `binds."<chord>".<action> = …`                              |
| per-bind properties                          | yes                          | `_props.allow-when-locked = true`                           |
| repeated nodes such as `spawn-at-startup`    | yes                          | `_children = [ { spawn-at-startup._args = [ … ]; } … ]`     |
| ordered window rules                         | yes, but only as `_children` | `_children = map (r: { window-rule._children = r; }) rules` |
| ordered outputs and workspaces               | yes, but only as `_children` | `output._args = [ name ]`, `workspace._args = [ name ]`     |
| raw KDL comments                             | no                           | `extraConfig`                                               |
| KDL raw strings `r#"…"#`                     | no                           | escaped strings are equivalent                              |
| Nix paths                                    | no                           | pass strings                                                |
| cross-file overrides of non-merging sections | not reliably                 | `include` is positional; keep one file                      |

The three composition traps:

1. A list of attribute sets becomes `-` children. Use `_children`.
2. Alphabetical order breaks window-rule priority. Use `_children`.
3. `listOf` values concatenate across module definitions. Two definitions of one `spawn` become two
   arguments. Enforce one definition site per list, or use `mkForce` on the whole list.

`niri validate` catches the first two at build time. The third is a silent semantic change, so the
typed surface must avoid it by construction.

## 5. `niri-flake`

`niri-flake` (https://github.com/sodiboo/niri-flake) is alive. It offers:

- a fully typed `programs.niri.settings` schema, with ordered sections and an action enum generated
  from the pinned niri source;
- `programs.niri.config` with a structured KDL algebra;
- `nixosModules.niri`, which disables the nixpkgs module;
- `homeModules.config`, `homeModules.niri`, and `homeModules.stylix`.

It is not a good dependency for this repo:

- It adds a fourth flake input with its own nixpkgs pin and binary cache.
- Its `nixosModules.niri` disables the nixpkgs module, so the repo loses control of the polkit,
  keyring, and portal choices that `desktop-base` already owns.
- Its stable package is behind the pinned nixpkgs, and its schema is already missing newer sections
  such as `recent-windows` and `blur`.

The repo should borrow the shape, not the code. A repo-local typed surface can render to the pinned
Home Manager module and validate against the pinned niri.

## 6. Session paths

| Path          | What happens                                                    |
| ------------- | --------------------------------------------------------------- |
| SDDM or GDM   | `niri.desktop` has `Exec=niri-session`                          |
| TTY           | `niri-session`                                                  |
| No systemd    | `niri --session`                                                |
| Nested window | plain `niri`                                                    |
| UWSM          | `uwsm start -- niri`, `-- niri --session`, or `-- niri-session` |

`niri-session`:

1. Detects external session management through `MANAGERPID` and `SYSTEMD_EXEC_PID`.
2. Re-execs through the login shell if needed.
3. Refuses a second session if `niri.service` is active.
4. Runs `systemctl --user reset-failed`, `systemctl --user import-environment`, and
   `dbus-update-activation-environment --all`.
5. Runs `systemctl --user --wait start niri.service`.
6. Starts `niri-shutdown.target` after the compositor exits.
7. Unsets the session variables.

`niri.service` has `BindsTo=graphical-session.target`, `Before=graphical-session.target`,
`Wants=graphical-session-pre.target`, `Wants=xdg-desktop-autostart.target`, `Type=notify`,
`Slice=session.slice`.

`niri-shutdown.target` has `Conflicts=graphical-session.target graphical-session-pre.target` and
`StopWhenUnneeded=true`.

Niri imports exactly five variables into the user manager and D-Bus: `WAYLAND_DISPLAY`, `DISPLAY`,
`XDG_CURRENT_DESKTOP`, `XDG_SESSION_TYPE`, and `NIRI_SOCKET`.

Niri hardcodes `XDG_CURRENT_DESKTOP=niri`. The KDL `environment {}` section does not propagate to
the systemd user manager.

## 7. UWSM interaction

UWSM supports niri through `uwsm-plugins/niri.sh`:

- `quirks_niri` appends `niri` to `XDG_CURRENT_DESKTOP`.
- `UWSM_FINALIZE_VARNAMES` includes `NIRI_SOCKET`, `XCURSOR_SIZE`, and `XCURSOR_THEME`.
- `quirks_niri_session` also waits for `NIRI_SOCKET`.

The start forms differ:

| Form                           | Consequence                                                                                                                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `uwsm start -- niri`           | UWSM owns the session. Niri does not import its own environment. The config must call `uwsm finalize NIRI_SOCKET`, or the waitenv service fails after its timeout.                                     |
| `uwsm start -- niri --session` | Niri imports its own environment. No finalize is needed. The plugin does not wait for `NIRI_SOCKET`.                                                                                                   |
| `uwsm start -- niri-session`   | `niri-session` detects UWSM and execs `niri --session`. The plugin waits for `NIRI_SOCKET`. This is two session managers in one path, and `niri-session` also calls `reset-failed` on unrelated units. |

UWSM gives a correct shutdown order, app slices, and XDG autostart. It costs the loss of custom
`XDG_CURRENT_DESKTOP` metadata, a plain-priority `dbus-broker` assignment, and a second session manager
to reason about.
Niri upstream does not recommend or mention UWSM.

## 8. Portals and screencast

| Item                   | Fact                                                                                                        |
| ---------------------- | ----------------------------------------------------------------------------------------------------------- |
| required portals       | `xdg-desktop-portal-gtk` as fallback, `xdg-desktop-portal-gnome` for screencast, `gnome-keyring` for Secret |
| packaged portal config | `niri-portals.conf` with `default=gnome;gtk;`, `Access=gtk`, `Notification=gtk`, `Secret=gnome-keyring`     |
| nixpkgs override       | `xdg.portal.config.niri` overrides the packaged config and disables `configPackages`                        |
| wlr portal             | not used; the module passes `enableWlrPortal = false`                                                       |
| screencast             | needs a working D-Bus session, pipewire, `xdg-desktop-portal-gnome`, and niri started as a session          |
| `wlr-screencopy`       | niri supports it, so `grim`, `slurp`, `wf-recorder`, and `wl-color-picker` work                             |
| idle inhibit           | niri implements `idle-inhibit`, `ext-idle-notify`, and `org.freedesktop.ScreenSaver`                        |

`GDK_BACKEND` must not be set globally. Upstream says it breaks the screencast portal.

The repo's Sway config sets `Inhibit = "none"` because the GTK portal reports success without an
implementation. Niri can answer `ScreenSaver.Inhibit`, so the Niri config can leave inhibit enabled.
This needs a live test.

## 9. Feature parity

| Sway workflow                | Niri equivalent                                                       | Parity                                              |
| ---------------------------- | --------------------------------------------------------------------- | --------------------------------------------------- |
| scrollable tiling            | columns on an infinite horizontal strip                               | different model                                     |
| `workspaceLayout = "tabbed"` | `default-column-display "tabbed"`                                     | approximate: tabs are per column, not per workspace |
| `layout stacking`            | none                                                                  | no                                                  |
| `layout toggle split`        | none                                                                  | no                                                  |
| `fullscreen`                 | `fullscreen-window`, `maximize-column`, `toggle-windowed-fullscreen`  | yes, more modes                                     |
| `floating toggle`            | `toggle-window-floating`, `move-window-to-floating`                   | yes                                                 |
| sticky                       | none (`niri#932`)                                                     | no                                                  |
| scratchpad                   | none                                                                  | no                                                  |
| `focus parent`               | none                                                                  | no                                                  |
| `focus next/prev sibling`    | `focus-window-up/down`                                                | approximate                                         |
| resize mode ladder           | `switch-preset-column-width`, `set-column-width`, `set-window-height` | approximate, no modes                               |
| passthrough mode             | `toggle-keyboard-shortcuts-inhibit`                                   | approximate                                         |
| `--release` binds            | none                                                                  | no; press with `repeat=false`                       |
| `--locked` binds             | `allow-when-locked=true`                                              | yes                                                 |
| `--inhibited` binds          | `allow-inhibiting=false`                                              | yes                                                 |
| static workspaces 1–10       | `focus-workspace N` or named workspaces                               | approximate                                         |
| move container to workspace  | `move-column-to-workspace N focus=false`                              | yes                                                 |
| move workspace to output     | `move-workspace-to-monitor-*`                                         | yes                                                 |
| `bindswitch` lid             | native lid handling plus `switch-events`                              | yes, better                                         |
| kanshi                       | works over `wlr-output-management`                                    | yes                                                 |
| waybar `sway/*`              | `niri/workspaces`, `niri/window`, `niri/language`                     | port needed                                         |
| swaync                       | works unchanged                                                       | yes                                                 |
| swayidle and swaylock        | work; DPMS becomes `power-off-monitors`                               | yes, small change                                   |
| swayr                        | `recent-windows`, `focus-window-previous`, `close-window`             | partial                                             |
| autotiling                   | meaningless in niri                                                   | dropped                                             |
| grim, slurp, wf-recorder     | work over `wlr-screencopy`                                            | yes                                                 |
| flameshot                    | expected, unverified                                                  | needs test                                          |
| `Super+P` nwg-displays       | works over `wlr-output-management`                                    | yes                                                 |
| `_sway-root-gui` xhost trick | none                                                                  | dropped                                             |
| XWayland                     | `xwayland-satellite`                                                  | port needed                                         |
| `wayvnc` input               | niri 26.04 has no virtual keyboard protocol                           | view-only                                           |
| headless output `HEADLESS-N` | no `create_output` and no headless backend                            | no                                                  |
| `sway-assign-cgroups`        | none                                                                  | no                                                  |
| config reload                | automatic plus `niri msg action load-config-file`                     | yes, better                                         |
| `exec` at startup            | `spawn-at-startup`                                                    | yes                                                 |
| `exec_always`                | none                                                                  | no                                                  |

## 10. Shortcut parity matrix

This is the summary matrix. The authoritative checklist is `shortcuts.research.md`, which has one row
per binding and the sign-off state. The 9 current accepted losses are Sway-specific and were signed
off on 2026-11-16.

| Sway bind                                      | Niri mapping                                                 | Status          |
| ---------------------------------------------- | ------------------------------------------------------------ | --------------- |
| `--release Super+V` paste                      | `Super+V` with `repeat=false`, action `spawn ydotool-paste`  | alternative     |
| `--inhibited --release Super+Ctrl+V` paste     | `Super+Ctrl+V` with `allow-inhibiting=false`, `repeat=false` | alternative     |
| `Alt+F4` kill                                  | `Alt+F4` `close-window`                                      | reproduced      |
| `Ctrl+Alt+Delete` wlogout                      | same, `spawn wlogout`                                        | reproduced      |
| `Super+E` file manager                         | same                                                         | reproduced      |
| `Super+K` calculator                           | same                                                         | reproduced      |
| `Super+Return` foot                            | same                                                         | reproduced      |
| `Super+D` nwg-drawer                           | same                                                         | reproduced      |
| `Alt+F2` wofi run                              | same                                                         | reproduced      |
| `Super+Shift+Q` kill                           | `close-window`                                               | reproduced      |
| `Super+Ctrl+S` layout stacking                 | none                                                         | accepted loss   |
| `Super+Ctrl+T` layout tabbed                   | `toggle-column-tabbed-display`                               | alternative     |
| `Super+Ctrl+E` layout toggle split             | none                                                         | accepted loss   |
| `Super+F` fullscreen                           | `fullscreen-window`                                          | reproduced      |
| `Super+Shift+F` floating                       | `toggle-window-floating`                                     | reproduced      |
| `Super+Shift+S` sticky                         | none                                                         | accepted loss   |
| `Super+R` resize mode                          | direct resize binds                                          | alternative     |
| `Super+Pause`, `Super+Scroll_Lock` passthrough | `toggle-keyboard-shortcuts-inhibit`                          | alternative     |
| `Super+A` focus parent                         | none                                                         | accepted loss   |
| `Super+Left/Down/Up/Right` focus               | `focus-column-left/right`, `focus-window-up/down`            | alternative     |
| `Super+mouse-up/down` focus                    | `Mod+WheelScroll*`; acts on the focused window               | alternative     |
| `Super+Shift+mouse-up/down` sibling focus      | none                                                         | accepted loss   |
| `Super+Shift+Left/Down/Up/Right` move          | `move-column-*`, `move-window-*`                             | alternative     |
| `Super+Shift+Ctrl+*` move workspace to output  | `move-workspace-to-monitor-*`                                | reproduced      |
| `Super+1..0` workspaces                        | `focus-workspace "1".."10"` or index                         | alternative     |
| `Super+Shift+1..0` move to workspace           | `move-column-to-workspace "N" focus=false`                   | reproduced      |
| `Super+Space` swayr switcher                   | `recent-windows` or `niri msg pick-window`                   | alternative     |
| `Super+Delete` swayr quit                      | `close-window`                                               | reproduced      |
| `Super+Tab` swayr urgent or LRU                | `recent-windows` next                                        | alternative     |
| `Alt+Tab`, `Alt+Shift+Tab` swayr               | `recent-windows` next/previous                               | alternative     |
| `Super+Shift+Space` swayr workspace or window  | none                                                         | accepted loss   |
| `Super+C`, `Super+Shift+C` swayr commands      | none                                                         | accepted loss   |
| `Super+L` lock                                 | `spawn swaylock -f`                                          | reproduced      |
| `Super+N` notification centre                  | `spawn swaync-client -t -sw`                                 | reproduced      |
| `Super+P` display editor                       | `spawn nwg-displays`                                         | reproduced      |
| `Super+O` open clipboard                       | same external command                                        | reproduced      |
| `Ctrl+Super+A` anonymise clipboard             | same external command                                        | reproduced      |
| brightness and volume keys                     | same external commands                                       | reproduced      |
| `--locked` media keys                          | `allow-when-locked=true`                                     | reproduced      |
| `Print` flameshot                              | `screenshot` or `spawn flameshot gui`                        | alternative     |
| `--inhibited Super+Print`                      | `allow-inhibiting=false`                                     | reproduced      |
| `Shift+Super+P` output toggle                  | `niri msg output eDP-1 off/on` script                        | alternative     |
| `XF86TouchpadToggle`                           | none                                                         | not bound today |
| lid close/open                                 | native                                                       | reproduced      |

## 11. Open questions

1. Does `flameshot` work under niri with the screencopy protocol? If not, use the native screenshot
   action.
2. Does `wlr/taskbar` `minimize-raise` work? Niri has no minimize concept.
3. Does `nwg-panel` in the pinned nixpkgs have the niri backend? The panel is disabled today, so
   this is low priority.
4. Does `waypipe` work under niri?
5. Does the Secret Service conflict need a portal override, or can `gnome-keyring` coexist with
   rosec?
6. Does the floating move/resize modifier have to be `Mod`, or can it be changed?
