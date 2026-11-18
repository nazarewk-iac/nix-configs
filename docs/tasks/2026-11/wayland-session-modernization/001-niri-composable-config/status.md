---
type: Status
description: The Niri PoC starts and works on brys, but the session services are Sway-scoped, so the bar, notifications, portals and XWayland do not start.
status: in-progress
authored_by: agent
timestamp: 2026-11-18T15:05:41+01:00
---

# Niri PoC — build-ready, live test pending

## What landed

| Piece          | Path                                   | State                                                                                              |
| -------------- | -------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Shared key map | `modules/den/common/desktop-niri.nix`  | Done. The 13 friendly names, `super` = `Mod`.                                                      |
| Niri aspect    | `modules/den/aspects/desktop-niri.nix` | Done. NixOS and Home Manager targets, typed option tree, `checkConfig = true`.                     |
| Registry       | `modules/den/lib.nix`                  | Done. `desktop-niri` entry.                                                                        |
| brys session   | `hosts-den/brys/default.nix`           | Done. `kdn.desktop-niri.session = "niri-session"`, `portal.secret = "none"`, `useNautilus = true`. |
| KDL validation | build                                  | `niri validate` passes on the generated `~/.config/niri/config.kdl`.                               |

The Sway tree is untouched, `defaultSession` is untouched, and the Sway shortcut set is still the
default session's.

## The generated surface

- `binds` reproduces the Sway catalog in
  [shortcuts.research.md](shortcuts.research.md): core binds, workspaces 1–10, the direct resize
  chords, media keys, application binds, and the swayr replacements.
- The nine signed-off `accepted-loss` rows are absent: sticky, scratchpad (not bound in Sway
  either), `layout stacking`, `focus parent`, the two sibling-focus wheel binds, and the two
  resize-mode exits.
- `spawn-at-startup` is empty on brys: the Home Manager `waybar`, `swaync` and `kanshi` services
  start from `graphical-session.target`, and native spawns would start a second copy. The aspect
  default keeps the three commands for a standalone consumer with no such services.
- `layout`, `input` and `animations` are typed sections. `extraKdl` is the escape hatch.
- The bind assertion fails the build on a duplicate chord or a missing `source`.

## Live test 2026-11-18 (brys, SDDM → `niri-session`)

What works:

- Login from the greeter. `loginctl` reports `Type=wayland`, `Desktop=niri`, `Active=yes`, seat0.
- The user manager carries `WAYLAND_DISPLAY=wayland-1`, `DISPLAY=:0`, `NIRI_SOCKET`,
  `XDG_CURRENT_DESKTOP=niri`, `XDG_SESSION_TYPE=wayland`.
- `Super+Enter` spawns the terminal; tiling and the keybinding overlay work.
- `niri msg --json outputs` reports `DP-4` at 2560x1440 — the real monitor, not the KVM.
- `rosecd.service` owns `org.freedesktop.secrets` (PID 33500 in the user manager).

What fails — **the session services are Sway-scoped**:

- `graphical-session.target` stays inactive. `niri.service` has
  `BindsTo=graphical-session.target`, but the start does not pull the target here.
- `waybar`, `swaync` and `kanshi` are `PartOf`/`WantedBy` `kdn-sway-kdn-sway-session.target`,
  not the generic target. They do not start in Niri, and a manual start dies with the Sway
  target.
- `xdg-desktop-portal*` are `requires`/`partOf` the Sway envs/session targets too. Starting the
  portal pulls the whole Sway graph: the Sway compositor started inside the Niri login, then
  failed on the DRM device, and its bar and autostart apps appeared on screen.
- `xwayland-satellite` is in `environment.systemPackages`, but nothing spawns it, so X11 clients
  have no path.

The unit graph that causes it (from `systemctl --user show`):

- `kdn-sway-kdn-sway-sway.service`: `bindsTo = [ "graphical-session.target" "...-session.target" ]`.
- `kdn-sway-kdn-sway-session.target`: `bindsTo = [ "graphical-session.target" "...-sway.service" ]`.
- `xdg-desktop-portal.service`: `requires = [ "...-envs.target" ]`,
  `partOf = [ "...-session.target" ]`.

So the build note "the Home Manager waybar, swaync and kanshi services start from
`graphical-session.target`" is wrong: they start from the Sway-specific target.

## What waits now

1. Walk [shortcuts.research.md](shortcuts.research.md) row by row; mark each `reproduced`,
   `alternative` or `accepted-loss`.
2. Record the UWSM A/B. The `niri-uwsm` branch exists (`kdn.desktop-niri.session`), and the
   plain `niri-session` is the control.
3. Decide the session-scope fix (below).

## The fix the test demands

1. Give Niri its own session scope, or make the shared services generic and make
   `niri.service` start `graphical-session.target`.
2. Keep the Sway compositor and its env/tray targets out of the generic target, so a Niri login
   cannot start Sway.
3. Spawn `xwayland-satellite` from the Niri session.
4. Decide the bar and notification config: the HM waybar config uses `sway/*` modules; Niri needs
   `niri/*` or compositor-agnostic modules.

## Known deviations from Sway

- Niri has no modes. `Super+R` cycles the preset column widths, and the resize chords act directly.
  The bare-arrow resize chords (`Left`, `Right`, `Up`, `Down`) are **not** bound, because they
  would take the arrow keys from every application.
- `Super+Space`, `Super+Tab` and `Alt+Tab` use `focus-window-previous`; Niri has no
  `recent-windows` action in 26.04.
- `move-column-to-workspace` keeps Niri's default focus behaviour; the Sway binding does not follow
  the window. A live decision is needed if the difference matters.

## Fixed after the live test

- The shared services moved to `graphical-session.target`: waybar, swaync, kanshi, the portals,
  the polkit agent and the secret service. The Sway envs target is ordering only.
- `niri.service` gets `Wants=graphical-session.target`, so the plain `niri-session` control starts
  the services too.
- `Niri (UWSM)` is generated as well; it needs `niri --session` (see
  [../002-sway-uwsm-session/status.md](../002-sway-uwsm-session/status.md)).
- keepassxc now starts after the generic target. It had aborted in Qt's `init_platform` because it
  started before the session environment existed.
- nwg-panel creates its runtime config directory before the first write.
- The waybar/`tray.target` ordering cycle is gone, so a logout stops `graphical-session.target` and
  the next login starts a fresh set.

Verified on brys: plain `Niri` and `Niri (UWSM)` both start waybar (tray host), swaync, kanshi,
the portals, keepassxc, kdeconnect, blueman, flameshot and rosecd. `nextcloud-client` needed
`startInBackground = false` to stay active.

## Verification commands

```bash
nix build --no-eval-cache '.#denConfigurations.brys.config.home-manager.users.kdn.xdg.configFile."niri/config.kdl".source'
nix build --no-eval-cache '.#denConfigurations.brys.config.system.build.toplevel'
nix eval --json '.#denConfigurations.brys.config.programs.niri.enable'
```
