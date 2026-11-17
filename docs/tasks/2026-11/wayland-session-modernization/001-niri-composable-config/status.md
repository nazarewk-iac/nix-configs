---
type: Status
description: The Niri PoC is implemented and build-validated on the den tree; the live session checklist waits for brys to return.
status: parked
authored_by: agent
timestamp: 2026-11-17T13:00:00+01:00
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

## What waits for the live test

1. Log in to `niri-session` from SDDM on brys.
2. Walk [shortcuts.research.md](shortcuts.research.md) row by row; mark each `reproduced`,
   `alternative` or `accepted-loss`.
3. Confirm `systemctl --user show-environment` carries `WAYLAND_DISPLAY`, `DISPLAY`,
   `NIRI_SOCKET`, `XDG_CURRENT_DESKTOP`.
4. Confirm portals and screencast, XWayland (`xwayland-satellite`), waybar, swaync, swaylock,
   swayidle, screenshots.
5. Record the UWSM A/B. The `niri-uwsm` branch exists (`kdn.desktop-niri.session`), and the
   plain `niri-session` is the control.
6. Decide the Secret Service owner. The PoC sets `portal.secret = "none"`, so the repository's
   `kdn-secret-service` owns `org.freedesktop.secrets` and the portal starts no second keyring.

## Known deviations from Sway

- Niri has no modes. `Super+R` cycles the preset column widths, and the resize chords act directly.
  The bare-arrow resize chords (`Left`, `Right`, `Up`, `Down`) are **not** bound, because they
  would take the arrow keys from every application.
- `Super+Space`, `Super+Tab` and `Alt+Tab` use `focus-window-previous`; Niri has no
  `recent-windows` action in 26.04.
- `move-column-to-workspace` keeps Niri's default focus behaviour; the Sway binding does not follow
  the window. A live decision is needed if the difference matters.

## Verification commands

```bash
nix build --no-eval-cache '.#denConfigurations.brys.config.home-manager.users.kdn.xdg.configFile."niri/config.kdl".source'
nix build --no-eval-cache '.#denConfigurations.brys.config.system.build.toplevel'
nix eval --json '.#denConfigurations.brys.config.programs.niri.enable'
```
