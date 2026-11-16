---
type: Task
description: Replace the hand-rolled Sway session with UWSM so an exit or crash can be followed by a fresh login without a reboot, while every Sway shortcut stays unchanged.
status: open
authored_by: agent
timestamp: 2026-11-16T17:14:00+01:00
---

# Sway session simplification with UWSM

Parent: [../definition.md](../definition.md)

## Problem

The Sway session is a hand-rolled UWSM. A custom desktop entry runs `kdn-sway-start`, which clears
and loads the environment, then starts `kdn-sway-kdn-sway-sway.service`. A set of custom targets
orders the environment, tray, portals, polkit, and secret service.

The known symptoms are recorded as TODOs at `modules/universal/desktop/sway/default.nix:14-16` and
`modules/den/aspects/desktop-sway.nix:601-603`:

- exiting Sway does not stop or restart `sddm-helper` or `display-manager.service`;
- exiting Sway a second time cannot `systemctl restart display-manager.service`;
- exiting Sway logs out all SSH sessions;
- after a Sway crash, Sway cannot start again without a reboot to clear systemd state.

The common cause is structural. The compositor starts through a proxy script outside the logind
session, and the custom unit graph has no shutdown contract. `envs.service` stays `active (exited)`.
Failed units are never collected. `graphical-session.target` is never stopped. `env-clear` wipes the
whole user-manager environment.

The full audit is in [research.md](research.md).

## Goal

One UWSM-managed Sway session (`sway-uwsm`) that:

- starts from SDDM with the same Sway configuration and every current keybinding;
- hands the environment to systemd and D-Bus through UWSM's delta preloader;
- tears the whole session down in order on exit or crash;
- lets the user log in again after a crash without a reboot;
- removes the hand-rolled `envs`, `tray`, and `session` targets and the custom `start` and `env-*`
  scripts;
- keeps the polkit agent, secret-service shim, portals, and applets working.

## Non-goals

- Changing Sway keybindings or the Sway workflow. This task changes the session layer only.
- Migrating to Niri. [001-niri-composable-config](../001-niri-composable-config/definition.md) owns
  that.
- Fixing SDDM upstream. The SDDM exit-code bug is documented and worked around, not patched.
- Removing the `sway-vnc` or headless path.

## Hard requirements

1. **Shortcut preservation.** The Sway configuration, including every binding from `keys.nix`,
   `home-manager/default.nix`, `media-keys.nix`, `swaylock.nix`, `swaync`, `nwg-shell`, `swayr`,
   `handlr`, `default-secrets`, and the host-level binds, is unchanged. A post-migration checklist
   proves every binding still works.
2. **A/B coexistence.** The old `kdn-sway` session stays available until the new session proves
   itself.
3. **Both trees in sync.** `modules/universal/**` and `modules/den/**` change together, and the den
   assertions are updated in the same change.
4. **No stale state.** After a normal exit, a crash, and a second exit, the user manager has no
   leftover `active (exited)` session units and no start-limit failure that blocks a new login.
5. **SSH sessions survive a Sway exit.** The symptom is reproduced or proven absent before the task
   is called done.

## Proposed approach

### Phase 0 — reproduce and instrument

On the test host, record the state before any change:

- `systemctl --user list-units 'kdn-sway-*' 'dbus-kdn-sway-*'`;
- `systemctl --user show-environment`;
- `loginctl list-sessions`;
- `journalctl -b -u display-manager`;
- `systemctl status display-manager`.

Reproduce these cases:

1. exit Sway;
2. exit Sway a second time;
3. `kill -SEGV` the Sway process;
4. start Sway again;
5. keep one SSH session open through all of the above.

Confirm or reject the root causes: stale `envs.service`, the circular `envs` to `sway` wait, the
`display-manager` start limit, and the `env-clear` blast radius.

### Phase 1 — add UWSM beside the current session

```nix
programs.uwsm = {
  enable = true;
  waylandCompositors.sway = {
    prettyName = "Sway";
    comment = "Sway managed by UWSM";
    binPath = "/run/current-system/sw/bin/sway";
    extraArgs = [ ];
  };
};
```

Keep `defaultSession = "kdn-sway"`. The greeter lists both `kdn-sway` and `sway-uwsm`. Do not remove
any existing unit yet. Prove that the new session starts and tears down.

### Phase 2 — make the UWSM session complete

- Add `exec uwsm finalize SWAYSOCK I3SOCK XCURSOR_SIZE XCURSOR_THEME` to the managed Sway config.
  Replace the `99-notify-systemd-service` fragment.
- Decide the environment carrier. Either keep `programs.sway.extraSessionCommands` with the base
  wrapper, or move the environment into `uwsm/env` fragments. Do not disable the base wrapper while
  `extraSessionCommands` is non-empty; the package asserts against that.
- Decide whether to keep the nixpkgs `/etc/sway/config.d/nixos.conf`. It imports the environment and
  starts `sway-session.target`. UWSM does the first. The second is redundant.
- Re-point every consumer from `kdn-sway-kdn-sway-envs.target` and `wayland.systemd.target` to
  `graphical-session.target` or `wayland-session@sway.target`.

The mapping is in [research.md §7](research.md#7-unit-mapping).

### Phase 3 — delete the hand-rolled graph

Delete:

- `kdn-sway-kdn-sway-sway.service`;
- `kdn-sway-kdn-sway-session.target`;
- `kdn-sway-kdn-sway-envs.service` and `envs.target`;
- `kdn-sway-kdn-sway-tray.target`;
- the `start`, `env-load`, `env-clear`, and `env-wait` scripts;
- the custom desktop entry;
- the `initScripts.systemd` pair.

Keep:

- `start-headless` and the `sway-vnc` path;
- the polkit agent, secret-service shim, portal overrides, gpg-agent, applets, and tray clients;
- the Sway keybindings and window rules.

Flip `defaultSession` to `sway-uwsm`. Remove `sessionPackages = [ cfg.bundle ]`.

### Phase 4 — verify

Repeat the Phase 0 matrix. Expected results:

- an exit returns to the greeter;
- a second exit also returns;
- a crash is followed by a new login without a reboot;
- no stale session unit remains;
- SSH sessions are unaffected.

Run the Sway shortcut checklist. Confirm portals, polkit, secret service, tray, media keys,
screenshots, and XWayland. Confirm that `nixos-rebuild switch` does not restart the compositor.

### Phase 5 — clean up and document

- Update `docs/post-change-checks.md`, which names the old units.
- Update `checks/den-mvp/assertions/sway-core.nix`, `desktop-leaves.nix`, and `tests.nix`.
- Write `done.md` with the root cause, the unit mapping, and the verification transcript.
- If the SSH symptom remains, keep the task open with `status.md` and a narrowed reproduction.

## Deliverables

| File          | Contents                                                                                                  |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| `research.md` | Unit inventory, start and stop traces, root causes, UWSM mapping, checks to update.                       |
| Nix changes   | `programs.uwsm`, `waylandCompositors.sway`, re-pointed units, deleted bundle scripts, updated den aspect. |
| Checks        | Updated den assertions and a new assertion for the UWSM session entry and the absence of the old units.   |
| Docs          | `docs/post-change-checks.md` update and `done.md` with the verification.                                  |

## Acceptance criteria

- [ ] `sway-uwsm` appears in SDDM and logs in on the test host.
- [ ] `systemctl --user show-environment` contains `WAYLAND_DISPLAY` and the UWSM-imported variables.
- [ ] Exiting Sway returns to the greeter, and a second exit also returns.
- [ ] `kill -SEGV` on the Sway process, then a new login, succeeds without a reboot.
- [ ] No `active (exited)` `kdn-sway-*` session unit remains after an exit.
- [ ] Every Sway binding in the shortcut checklist works unchanged.
- [ ] Portals, polkit, secret service, tray, media keys, screenshots, and XWayland work.
- [ ] SSH sessions are unaffected by a Sway exit, or the remaining cause is documented.
- [ ] Both `modules/universal` and `modules/den` are updated, and the den checks pass.
- [ ] `nixos-rebuild switch` does not restart the compositor.

## Risks

- UWSM assigns `services.dbus.implementation = "broker"` at plain priority. The nixpkgs default is
  already `broker`, so this is a no-op unless a host sets `"dbus"`, which would conflict.
- The first UWSM login may run on top of a stale user manager. Reboot once after the switch, or stop
  the old units manually.
- `XDG_CURRENT_DESKTOP` may change from `sway` to `sway:wlroots`, which changes portal backend
  selection.
- The SDDM exit-code bug remains. An abnormal teardown can still leave a black screen until
  `sddm#1908` is fixed.
- `uwsm start` may wait up to 60 s for the system `graphical.target`. Use `-g -1` or `-G -1` if the
  boot blocks on the network.
- Removing `env-clear` changes what survives between sessions. Applications that relied on the
  blanket wipe may behave differently.
- The doubled-prefix unit names are pinned by checks and may be referenced by operators. The
  migration must update both.

## Open questions

1. Which host is the test host? It needs SDDM, Sway, and a spare login.
2. Does the SSH-logout symptom reproduce? If not, close it as "not reproducible" with the collected
   evidence.
3. Is `programs.sway.extraSessionCommands` kept, or does the environment move to `uwsm/env`?
4. Is `defaultSession` flipped in the same change, or after a week of A/B?
5. Is the nixpkgs `sway-session.target` kept or disabled?
