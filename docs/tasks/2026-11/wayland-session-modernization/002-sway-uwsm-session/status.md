---
type: Status
description: The opt-in UWSM A/B session is in both trees and build-proven; the destructive phase waits for the live A/B.
status: parked
authored_by: agent
timestamp: 2026-11-18T00:15:00+01:00
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
