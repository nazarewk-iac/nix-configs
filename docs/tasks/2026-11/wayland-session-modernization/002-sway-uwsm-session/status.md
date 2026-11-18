---
type: Status
description: Both UWSM sessions ran live on brys; the session services now start from the generic target, and Niri needs `--session` for UWSM's notify handshake.
status: in-progress
authored_by: agent
timestamp: 2026-11-18T15:12:35+01:00
---

# Sway/UWSM A/B — built, opt-in, live test pending

## What landed

| Tree      | Option                         | Default | Effect                                                              |
| --------- | ------------------------------ | ------- | ------------------------------------------------------------------- |
| universal | `kdn.desktop.sway.uwsm.enable` | `false` | Adds `programs.uwsm` and the `sway-uwsm` session beside `kdn-sway`. |
| den       | `kdn.desktop-sway.uwsm.use`    | `false` | The same, through the den aspect.                                   |

The option changes no Sway unit, no environment, no portal and no `defaultSession`. It only makes
the greeter list a second entry. A build with the option on produces the session set
`kdn-sway-bundle`, `sway-uwsm`, `sway` (and `niri` on the den host), with `defaultSession` still
`kdn-sway`.

## How to run the A/B

On brys, with either tree:

```nix
kdn.desktop-sway.uwsm.use = true;     # den
kdn.desktop.sway.uwsm.enable = true;  # universal
```

Rebuild and switch, then log in to `Sway (UWSM)` from the greeter. The control session is still
`kdn-sway`.

## What the live A/B must prove

1. The UWSM session reaches `graphical-session.target` and carries `WAYLAND_DISPLAY`, `DISPLAY`,
   `SWAYSOCK` and `XCURSOR_*` into the user manager.
2. Portals, polkit, the secret service, waybar, swaync, swaylock/swayidle, screenshots and
   XWayland behave as in `kdn-sway`.
3. Exit, second exit and crash-then-relogin do not need a reboot.
4. SSH sessions survive an exit.
5. `nixos-rebuild switch` does not restart the compositor.

The task's scorecard and the full phase plan live in [definition.md](definition.md).

## Live A/B 2026-11-18 (brys, den, `kdn.desktop-sway.uwsm.use = true`)

### `Sway (UWSM)`

- `graphical-session.target` is active, `wayland-wm@sway.service` runs the compositor, and
  `SWAYSOCK` plus `XCURSOR_*` reach the user manager.
- Portals (gateway, gtk, wlr), `rosecd` and swaync start.
- waybar and kanshi did **not** start: the Home Manager `wayland.systemd.target` was the
  Sway-specific `kdn-sway-…-session.target`. The den aspect now points it at
  `graphical-session.target`, and the Sway envs target is ordering only (`After`, never
  `Requires`), so a Niri or UWSM login cannot wait for a Sway-only unit.

### `Niri (UWSM)`

- Supported: `programs.uwsm.waylandCompositors.niri` generates `Niri (UWSM)`.
- The entry **must** pass `niri --session`. Plain `niri` never runs `uwsm finalize`, so
  `wayland-wm@niri.service` stays in `Type=notify`-activating, the session target never starts,
  and the login shows a bare desktop. Measured 2026-11-18: `graphical-session.target` inactive,
  no `NIRI_SOCKET` in the manager, `wayland-wm@niri.service` dead after the timeout.
- With `--session`, `NIRI_SOCKET`/`WAYLAND_DISPLAY` reach the manager and the same app set starts.

### The app set (both Niri sessions)

Active after the fixes: waybar (the tray host), swaync, kanshi, `xdg-desktop-portal`
(+gtk, wlr), keepassxc, kdeconnect, blueman-applet, flameshot, rosecd.

- `nextcloud-client`: `startInBackground = true` adds `--background`, which forks; the
  `Type=simple` unit went inactive within a second and no tray icon appeared. The den aspect now
  runs the client in the foreground.
- `nwg-panel` is Sway-only and stays inactive under Niri.

### The ordering cycle that leaked a whole session

waybar had `BindsTo=tray.target`; `tray.target` Wants waybar; flameshot Requires `tray.target`;
flameshot is `PartOf` the generic target; the target Wants waybar. On logout systemd logged
`Found ordering cycle … Unable to break cycle starting with graphical-session.target/stop`, so the
target never stopped. The next login found it already active, started none of its Wants, and the
old session's apps stayed on screen. Dropping `BindsTo=tray.target` broke the cycle; the target now
stops cleanly and each login starts a fresh set.

### Two more cycles, and the lingering-manager trap

- flameshot had `After`/`Requires` `tray.target`; `tray.target` Wants waybar; waybar is wanted by
  `graphical-session.target`; flameshot is ordered after that target. Under UWSM systemd deleted
  flameshot's start job to break the cycle, so the unit failed with no useful error. The tray
  coupling is gone; only the Sway envs target remains as ordering.
- nextcloud-client quits when it finds no StatusNotifier host. Waybar starts in the same
  transaction, so the client now waits 2 s before it checks.
- With `linger = true` the user manager survives a logout. A Niri-UWSM session leaves
  `wayland-session-pre@niri.target` and `graphical-session-pre.target` active, and the next UWSM
  login refuses to start: "A compositor or graphical-session* target is already active". The units
  refuse manual stop; starting `wayland-session-shutdown.target` clears them. This is the one
  remaining blocker for switching between UWSM sessions without a reboot.

### Still open from the scorecard

- Exit, second exit and crash-then-relogin (the stop path now works, but the crash case is not
  exercised).
- `nixos-rebuild switch` not restarting the compositor (the test restarted `display-manager`
  explicitly).

## What still waits

- Phase 2 of the task: the `uwsm finalize SWAYSOCK I3SOCK …` line, the environment carrier decision,
  and the re-pointing of the custom session consumers.
- Phase 3: delete the hand-rolled `kdn-sway-*` graph and flip `defaultSession`.
- Both phases are destructive and need the live results; the opt-in A/B is the reversible step that
  produces them.

## Verification commands

```bash
nix build --no-eval-cache '.#denConfigurations.brys.config.system.build.toplevel'
nix build --no-eval-cache '.#nixosConfigurations.brys.config.system.build.toplevel'
nix eval --json '.#denConfigurations.brys.config.services.displayManager.defaultSession'  # kdn-sway
```
