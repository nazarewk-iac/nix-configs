---
type: Research
description: Audit of the current Sway session graph, the start and stop traces, the root causes of the recorded symptoms, and the UWSM unit mapping.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T17:16:00+01:00
---

# Sway session audit

Sources: the repo files, the pinned nixpkgs and home-manager store paths from
[../research.md](../research.md), and the systemd manual pages. The audit is read-only. No host was
changed.

## 1. Unit inventory

The name construction doubles the prefix. `kdn.desktop.sway.systemd` defaults `prefixes` to
`[ entry prefix, aspect prefix ]`, and both are `"kdn-sway"`
(`modules/universal/desktop/sway/default.nix:101-130`; den port
`modules/den/aspects/desktop-sway.nix:443-470`). Live names therefore read
`kdn-sway-kdn-sway-…`. The den checks pin this on purpose
(`checks/den-mvp/assertions/sway-core.nix:147-166`).

| Unit                                     | Key directives                                                                                                                                                                                                                                                                                                   | Source                                 |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `kdn-sway-kdn-sway-sway.service`         | `Type=notify`, `NotifyAccess=all`, `Slice=session.slice`, `BindsTo=graphical-session.target + session.target`, `Requires=graphical-session-pre.target`, `Before=graphical-session.target`, `ExecStopPost=env-clear`, `Restart=no`, `TimeoutStartSec=300`, `TimeoutStopSec=60`, `environment.PATH = mkForce null` | `sway/default.nix:258-289`             |
| `kdn-sway-kdn-sway-session.target`       | `BindsTo=graphical-session.target + sway.service`, `Requires=graphical-session-pre.target + envs.target + tray.target`, `Before=graphical-session.target`, `After=…`                                                                                                                                             | `sway/default.nix:291-309`             |
| `kdn-sway-kdn-sway-envs.service`         | `Type=oneshot`, `RemainAfterExit=true`, `ExecStart=env-wait --show --progress`, `sleep 2`, `echo`, and `systemctl stop --user gpg-agent` when gpg is on                                                                                                                                                          | `sway/default.nix:317-326`, `:548-554` |
| `kdn-sway-kdn-sway-envs.target`          | `PartOf=session.target`, `BindsTo=envs.service`, `After=envs.service`                                                                                                                                                                                                                                            | `sway/default.nix:311-316`             |
| `kdn-sway-kdn-sway-tray.target`          | `BindsTo=tray.target`, `Before=session.target + tray.target`, `After=envs.target`, `Requires=envs.target`; no `PartOf`                                                                                                                                                                                           | `sway/default.nix:328-337`             |
| `kdn-sway-kdn-sway-polkit-agent.service` | `PartOf=session.target`, `Requires=envs.target`, `After=envs.target`, `Slice=background.slice`, `script=polkit agent`                                                                                                                                                                                            | `sway/default.nix:353-360`             |
| `dbus-kdn-sway-secrets-service.service`  | `Type=dbus`, `BusName=org.freedesktop.secrets`, `ExecStart=sleep infinity` (default), `PartOf=session.target`, `Requires=envs.target`, `After=envs.target`, `TimeoutStartSec=120s`                                                                                                                               | `sway/default.nix:525-546`             |
| `dbus-kdn-sway-secrets-service.target`   | `BindsTo=service`, `Requires=envs.target`, `After=envs.target`                                                                                                                                                                                                                                                   | `sway/default.nix:518-523`             |
| `xdg-desktop-portal.service`             | `Requires=envs.target`, `After=envs.target`, `PartOf=session.target`, `Slice=background.slice`                                                                                                                                                                                                                   | `sway/default.nix:339-344`             |
| `xdg-desktop-portal-gtk.service`         | same as above                                                                                                                                                                                                                                                                                                    | `sway/default.nix:346-351`             |
| `xdg-desktop-portal-wlr.service`         | no `envs` dependency; `ConditionEnvironment=WAYLAND_DISPLAY` from the package                                                                                                                                                                                                                                    | `sway/default.nix:467-496`             |
| `gpg-agent.service`                      | `PartOf=envs.target`, `StopPropagatedFrom=envs.target`, `After=envs.target`, `Slice=background.slice`                                                                                                                                                                                                            | `sway/default.nix:555-562`             |

Pulled in by `programs.sway.enable`:

| Unit or file                                      | Effect                                                                                                                                                             | Source                                                      |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| `sway-session.target`                             | `BindsTo=graphical-session.target`, `Wants=graphical-session-pre.target`, `After=graphical-session-pre.target`                                                     | `<nixpkgs>/nixos/modules/programs/wayland/sway.nix:173-179` |
| `/etc/sway/config.d/nixos.conf`                   | `dbus-update-activation-environment --systemd …`, `systemctl --user import-environment …`, `systemctl --user start sway-session.target`, and a shutdown subscriber | `<nixpkgs>/nixos/modules/programs/wayland/sway.nix:158-166` |
| `services.displayManager.sessionPackages += sway` | a second session entry named `sway`, next to `kdn-sway`                                                                                                            | `<nixpkgs>/nixos/modules/programs/wayland/sway.nix:182`     |

Home Manager units in the graph:

| Unit                                       | Session binding                                                                                                                                                       | Source                                                     |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `waybar.service`                           | `BindsTo=tray.target`, `PartOf=tray.target + session.target`, `Requires=envs.target`, `ConditionEnvironment=WAYLAND_DISPLAY`, `WantedBy=tray.target + session.target` | `sway/home-manager/waybar.nix:221-224`                     |
| `kanshi.service`                           | `PartOf`, `Requires`, `After`, `WantedBy=session.target`                                                                                                              | `sway/home-manager/default.nix:331`                        |
| `swayidle.service`                         | `PartOf`, `After`, `WantedBy=session.target` plus `envs.target`                                                                                                       | `sway/home-manager/swaylock.nix:42-45`                     |
| `swaync.service`                           | `PartOf`, `After=session.target`, `Type=dbus`                                                                                                                         | bundled HM module                                          |
| `network-manager-applet.service`           | `After=graphical-session.target + tray.target + envs.target`, `Requires=envs.target`                                                                                  | `sway/home-manager/default.nix:54-58`                      |
| `blueman-applet.service`                   | `After=…`, `Requires=tray.target + envs.target`                                                                                                                       | `sway/home-manager/default.nix:61-72`                      |
| `flameshot.service`                        | `After=tray.target + envs.target`; the `mkForce` drops `After=graphical-session.target`                                                                               | `sway/home-manager/default.nix:93-102`                     |
| `keepassxc.service`                        | `WantedBy=graphical-session.target`, `Slice=background.slice`                                                                                                         | `modules/universal/programs/keepassxc/default.nix:115-146` |
| `nextcloud-client`, `avizo`, `kdeconnect*` | `WantedBy=graphical-session.target` or `session.target`                                                                                                               | bundled modules                                            |

## 2. Start sequence

1. Boot reaches `graphical.target`, which wants `display-manager.service`.
2. SDDM runs its Weston kiosk greeter. The greeter reads `kdn-sway.desktop`.
3. SDDM forks the session `Exec=`: `kdn-sway-start --wait --ignore-error`
   (`bundle.nix:156-167`).
4. `kdn-sway-start` runs `env-clear` and `env-load` (`bundle.nix:26-27`). `env-clear` unsets every
   variable in the user manager and empties every variable on the session bus. `env-load` imports
   the whole SDDM environment (`bundle.nix:47-92`).
5. `kdn-sway-start` runs `systemctl --user start kdn-sway-kdn-sway-sway.service --wait`.
6. The start job pulls in `graphical-session.target`, `session.target`, `envs.target`,
   `envs.service`, `tray.target`, and `graphical-session-pre.target` through `BindsTo` and
   `Requires`.
7. `sway.service` runs the nixpkgs wrapper. The wrapper exports `XDG_CURRENT_DESKTOP=sway`, runs
   `programs.sway.extraSessionCommands`, renames `NOTIFY_SOCKET` to `KDN_SWAY_NOTIFY_SOCKET`, sources
   `/etc/profile`, exports the configured environment, and execs `sway`.
8. The Sway config includes `/etc/sway/config.d/*`. The repo fragment runs `env-load` again, now with
   `WAYLAND_DISPLAY`, then sends `READY=1` through the renamed socket.
9. `envs.service` sees `WAYLAND_DISPLAY` and `KDN_SWAY_SYSTEMD`, sleeps 2 s, and exits. Its
   `RemainAfterExit` keeps it active.
10. `envs.target` and `tray.target` activate. The applets, waybar, kanshi, swaync, swayidle, polkit
    agent, portals, and secret-service shim start.
11. `session.target` activates, then `graphical-session.target`. `kdn-sway-start` waits for
    `sway.service` to become inactive or failed, then returns. SDDM sees the session process exit.

Ordering problems in this sequence:

| #   | Problem                                                                                                      | Consequences                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| O1  | `envs.service` is a oneshot with no `TimeoutStartSec`.                                                       | The start job can wait forever. Every unit ordered after it waits too.                                                  |
| O2  | `sway.service` has no ordering against `envs.target` or `session.target`. The only sync is the polling loop. | A race between the compositor and the environment barrier.                                                              |
| O3  | `env-wait` uses a substring match over the whole environment dump.                                           | A stale value from a previous session satisfies the wait.                                                               |
| O4  | `READY=1` is the last step of a `set -e` script whose first step is `dbus-update-activation-environment`.    | Any failure hides the readiness notification. The unit sits in `activating` until `TimeoutStartSec=300`, then fails.    |
| O5  | `NotifyAccess=all` plus the `NOTIFY_SOCKET` rename.                                                          | The podman workaround is still needed, and every process in the cgroup can notify.                                      |
| O6  | `flameshot` loses `After=graphical-session.target` because `mkForce` replaces the whole list.                | A `WantedBy=graphical-session.target` unit with no ordering against it.                                                 |
| O7  | The secret-service unit is `Type=dbus`, but its `ExecStart` is `sleep infinity`.                             | Readiness depends on KeePassXC claiming the name, with a 120 s ceiling and unit rollback on timeout.                    |
| O8  | `xdg-desktop-portal-wlr` has no `envs` dependency, unlike its siblings.                                      | `ConditionEnvironment` can silently skip it when the environment is stale.                                              |
| O9  | Two session targets exist: the repo's and nixpkgs' `sway-session.target`.                                    | Both are started, and their ordering is unclear.                                                                        |
| O10 | `session.target` requires `tray.target`, while the repo tray target `BindsTo=tray.target`.                   | A stop or restart of `tray.target` stops `session.target`, which stops `sway.service`.                                  |
| O11 | `PATH` is force-unset on `sway.service`.                                                                     | Anything before `/etc/profile` runs without a useful `PATH`.                                                            |
| O12 | `env-clear` wipes every variable from the user manager and empties it on the session bus.                    | Later D-Bus activations and user units inherit empty `PATH`, `HOME`, `XDG_RUNTIME_DIR`, and `DBUS_SESSION_BUS_ADDRESS`. |

## 3. Stop and crash sequence

### 3.1 Normal exit

1. Sway exits. `ExecStopPost=env-clear` wipes the environment.
2. The unit becomes inactive or failed. `Restart=no` forbids a restart.
3. `BindsTo` stops `session.target`. `PartOf` stops `envs.target`, the polkit agent, the secret
   service, and the portals. `Requires=envs.target` stops the tray clients.
4. `graphical-session.target` loses its needers and stops itself.
5. `kdn-sway-start` returns. SDDM returns to the greeter. SDDM stays alive.

Not stopped:

- `envs.service` stays `active (exited)`.
- `tray.target` stays active.
- `dbus-kdn-sway-secrets-service.target` stays active.
- `graphical-session-pre.target` may stay active.
- `sway.service` stays `failed` after a non-zero exit.

### 3.2 Crash

The sequence is the same, except the unit lands in `failed` and the user manager keeps a failed
unit. No `CollectMode` unloads it. No `reset-failed` runs. The start-limit counter stays hot.

### 3.3 `systemctl restart display-manager.service`

`display-manager.service` has `Restart=always`, `StartLimitBurst=3`, and
`StartLimitIntervalSec=30` (`<nixpkgs>/nixos/modules/services/display-managers/generic.nix:56-83`).
Three rapid exits put the unit into `failed` with "start request repeated too quickly". A manual
restart is refused until `systemctl reset-failed display-manager.service`. A reboot also clears it.

## 4. Root causes of the four symptoms

| Symptom                                                   | Cause                                                                                                                                                                                                                                                                                                                                                                                                                               | Confidence         |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| Exiting Sway does not stop or restart the display manager | SDDM returns to the greeter by design when a session ends. If `kdn-sway-start` never returns, the greeter does not come back. The script can hang when `READY=1` is lost (O4), when the stop job burns `TimeoutStopSec=60`, or when the compositor is still alive.                                                                                                                                                                  | Medium-high        |
| A second exit cannot restart the display manager          | The `display-manager` start limit (3 starts in 30 s). A reboot clears it, `reset-failed` also clears it.                                                                                                                                                                                                                                                                                                                            | High               |
| After a crash, Sway needs a reboot                        | The custom graph has no shutdown contract. Stale `envs.service` (active-exited), stale `tray.target`, failed `sway.service`, hot start-limit counters, and a pending `envs.service` start job with no timeout. The next start waits for `WAYLAND_DISPLAY` and `KDN_SWAY_SYSTEMD`, which only a successful Sway start produces. That is a circular wait through polling. Lingering keeps the stale user manager alive across logins. | High               |
| Exiting Sway logs out all SSH sessions                    | Not reproduced in code review. See §5.                                                                                                                                                                                                                                                                                                                                                                                              | Needs a live repro |

The direct answer to "which unit lacks which dependency":

| Unit                                   | Missing dependency                      | Consequence                                                                 |
| -------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------- |
| `envs.service`                         | `PartOf=session.target`                 | never stops, never re-runs; the next session skips the environment handoff  |
| `envs.service`                         | `TimeoutStartSec`                       | infinite `activating`                                                       |
| `tray.target`                          | `PartOf=session.target`                 | survives the session; its `BindsTo` can also tear down the compositor (O10) |
| `dbus-kdn-sway-secrets-service.target` | `PartOf=session.target`                 | survives the session                                                        |
| `xdg-desktop-portal-wlr.service`       | `Requires=` and `After=envs.target`     | silently skipped when the environment is stale                              |
| `sway.service`                         | `PropagatesStopTo` or a shutdown target | no explicit stop contract; only implicit `BindsTo` propagation              |
| `tray.target` (Home Manager)           | `PartOf=graphical-session.target`       | stays active across sessions                                                |

## 5. Why SSH sessions might drop

Facts that rule out the textbook causes:

| Candidate                                     | Repo fact                                                                             | Verdict                          |
| --------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------- |
| `KillUserProcesses=yes`                       | nixpkgs sets `false` (`<nixpkgs>/nixos/modules/system/boot/systemd/logind.nix:20-43`) | ruled out                        |
| `logind` override                             | no `services.logind` in the repo                                                      | ruled out                        |
| `RemoveIPC=yes` on last-session exit          | lingering is on (`modules/universal/profile/user/kdn/default.nix:590`)                | ruled out if lingering is active |
| `user@UID.service` stops                      | lingering keeps it                                                                    | ruled out if lingering is active |
| `loginctl terminate-user`                     | no such call in the repo                                                              | ruled out                        |
| SSH sessions are children of the Sway session | possible for `ssh` started from a terminal                                            | needs a check                    |

Remaining candidates:

1. **Shared-environment poisoning.** `env-clear` runs at session start and at session stop. It
   unsets every variable in the user manager and empties every variable on the shared session bus.
   An SSH login that starts a user unit or a D-Bus activation afterwards inherits empty values. The
   SSH shell survives, but its environment is broken. This is the strongest code-level candidate.
2. **Lingering is not actually active on the host.** If `pam_systemd` is absent from the sshd PAM
   stack, the Sway session is the only logind session. At its end logind stops `user@`, removes
   `/run/user/UID`, and `RemoveIPC` can drop shared memory. Programs can then die.
3. **sshd was restarted by a dependency.** The repo has a documented SSH outage from
   `systemd.services.sshd` depending on `kdn-secrets.target`. If a rebuild happened at the same
   time, this is unrelated to Sway.
4. **The SSH sessions were children of the Sway session.** `ssh` from `foot` dies with the
   compositor. This is expected, not a bug.

The experiment set in §9 separates these.

## 6. Needed versus incidental

| Piece                                                                   | Verdict                                    | Reason                                                  |
| ----------------------------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------- |
| `env-load`                                                              | needed today, replaced by UWSM's preloader | systemd gives a session no environment                  |
| `env-clear`                                                             | incidental and harmful                     | UWSM cleans only the delta it added                     |
| `env-wait`                                                              | incidental                                 | replaced by `wayland-session-waitenv.service`           |
| `envs.service` and `envs.target`                                        | incidental                                 | pure workaround                                         |
| repo `tray.target`                                                      | incidental                                 | orders tray clients after the environment               |
| `kdn-sway-start` and the custom desktop entry                           | incidental                                 | replaced by `uwsm start` and `wayland-session-bindpid@` |
| `NotifyAccess=all` and the `NOTIFY_SOCKET` rename                       | incidental, but keep until tested          | podman workaround                                       |
| `start-headless`                                                        | app-specific                               | VNC and headless path                                   |
| polkit agent, secret-service shim, portal overrides, gpg-agent, applets | app-specific                               | keep and re-order                                       |
| nixpkgs `sway-session.target` and `nixos.conf`                          | duplicate                                  | UWSM does the same job                                  |

## 7. Unit mapping

| Current unit or file                                                          | Action under UWSM | Becomes                                                                                                                                           |
| ----------------------------------------------------------------------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `kdn-sway-kdn-sway-sway.service`                                              | replace           | `wayland-wm@sway.service`                                                                                                                         |
| `kdn-sway-kdn-sway-session.target`                                            | replace           | `wayland-session@sway.target` plus `graphical-session.target`                                                                                     |
| `kdn-sway-kdn-sway-envs.service`                                              | delete            | `wayland-wm-env@sway.service` and `wayland-session-waitenv.service`                                                                               |
| `kdn-sway-kdn-sway-envs.target`                                               | delete            | `wayland-session-pre@sway.target`                                                                                                                 |
| `kdn-sway-kdn-sway-tray.target`                                               | delete            | no equivalent; use `tray.target` and `graphical-session.target`                                                                                   |
| `kdn-sway-kdn-sway-polkit-agent.service`                                      | keep, re-order    | `PartOf=graphical-session.target`, `After=graphical-session.target`, `Slice=background-graphical.slice`                                           |
| `dbus-kdn-sway-secrets-service.*`                                             | keep, re-order    | drop `Requires=envs.target`; use `After=graphical-session.target`; keep `Type=dbus` and the activation file                                       |
| `gpg-agent` overrides                                                         | keep, simplify    | keep `PartOf` and `StopPropagatedFrom=graphical-session.target`; drop the `systemctl stop gpg-agent` line                                         |
| `xdg-desktop-portal{,-gtk,-wlr}`                                              | keep, re-order    | drop `envs` dependencies; add `After=graphical-session.target`; add the wlr backend to the same ordering                                          |
| `waybar`, `kanshi`, `swayidle`, `swaync`, `blueman`, `nm-applet`, `flameshot` | keep, re-order    | `wayland.systemd.target = "graphical-session.target"`; `services.kanshi.systemdTarget = "graphical-session.target"`; restore flameshot's ordering |
| `keepassxc`, `nextcloud-client`, `avizo`, `kdeconnect`                        | keep              | already use `graphical-session.target`                                                                                                            |
| nixpkgs `/etc/sway/config.d/nixos.conf`                                       | delete or disable | UWSM imports the environment and starts the session                                                                                               |
| repo `/etc/sway/config.d/00-kdn-sway-init.conf`                               | delete            | replaced by `exec uwsm finalize SWAYSOCK I3SOCK`                                                                                                  |
| `kdn-sway-start` and the desktop entry                                        | delete            | `programs.uwsm.waylandCompositors.sway`                                                                                                           |
| `display-manager.service`                                                     | keep              | unchanged                                                                                                                                         |
| `start-headless` and `sway-vnc`                                               | keep              | unchanged                                                                                                                                         |

Ordering that still works unchanged: `After=graphical-session-pre.target` units, units with
`WantedBy=graphical-session.target`, and units with `PartOf=graphical-session.target`. The last group
finally gets stopped, because UWSM's shutdown target conflicts `graphical-session.target`.

What conflicts outright:

- the two compositor units;
- `env-clear` versus UWSM's cleanup list;
- `env-load`'s blanket import versus UWSM's delta export;
- the doubled `kdn-sway-kdn-sway-session.target` versus UWSM's graph, which never starts it. Any
  service that waits on it never starts.

## 8. Checks and assertions to update

`checks/universal-guards.nix` has no Sway assertions. No update is needed there.

`checks/den-mvp/assertions/sway-core.nix`:

| Line    | Assertion                                                              | Pinned value                                                                                          |
| ------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| 147     | the session unit names carry the prefix twice                          | 7 exact unit strings                                                                                  |
| 168     | the shared `envsTarget` gets the computed name on both classes         | `kdn-sway-kdn-sway-envs.target`                                                                       |
| 179     | the nixos class declares the seven session units                       | 8 keys under `systemd.user.services` and `targets`                                                    |
| 204     | the nixos class turns Sway on and registers the session                | `defaultSession="kdn-sway"`, `providedSessions=["kdn-sway"]`                                          |
| 221     | the session bundle exports the six scripts                             | `env-clear`, `env-load`, `env-show`, `env-wait`, `start`, `start-headless`                            |
| 233     | the environment option sets keep their counts                          | `defaults=2`, `environment=9`                                                                         |
| 248     | the init scripts land in one drop-in                                   | `sway/config.d/00-kdn-sway-init.conf`                                                                 |
| 259     | the portal routes screencast and screenshot to wlr and refuses inhibit | portal config                                                                                         |
| 278     | the portal list holds GTK and wlroots                                  | backend names                                                                                         |
| 292     | the portal debug switch and the shared package stay off                | —                                                                                                     |
| 305     | the home class turns the Sway module on                                | `wayland.windowManager.sway.systemd.enable=false`, `waylandTarget="kdn-sway-kdn-sway-session.target"` |
| 318     | the home class stays inert on darwin                                   | —                                                                                                     |
| 331     | the home class states the keyboard layout and workspace layout         | —                                                                                                     |
| 349     | the lid switch names the output                                        | —                                                                                                     |
| 362     | the launcher keybinding reads the drawer                               | —                                                                                                     |
| 375     | kanshi starts from the Sway session target                             | `systemdTarget="kdn-sway-kdn-sway-session.target"`                                                    |
| 380     | the includes bundle loads the seven leaves and leaves the panel out    | —                                                                                                     |
| 399-436 | remote extras                                                          | —                                                                                                     |

`checks/den-mvp/assertions/desktop-leaves.nix`:

| Line | Assertion                                                   | Pinned value                                  |
| ---- | ----------------------------------------------------------- | --------------------------------------------- |
| 221  | each desktop leaf emits its classes                         | aspect names                                  |
| 264  | a graphical host raises the shared flag                     | `kdn.graphical`                               |
| 281  | SDDM runs on Wayland with the chili theme                   | SDDM shape                                    |
| 491  | the shared key map and session target hold the old defaults | `envsTarget="kdn-sway-envs.target"`           |
| 611  | waybar runs as a user service and reads one generated file  | `BindsTo tray.target`, `Requires envs.target` |
| 643  | kanshi runs and holds no monitor                            | —                                             |
| 797  | the panel reads its payload and runs as a unit              | `WantedBy=graphical-session.target`           |
| 840  | the lock runs on an idle timer                              | `After` and `Requires envs.target`            |

`checks/den-mvp/tests.nix` pins the aspect registry at `:620-629`. Add an entry if the migration adds
an aspect.

Minimum edit set if the session model changes: `sway-core.nix` 147, 168, 179, 204, 221, 233, 248,
305, 375, and the remote block; `desktop-leaves.nix` 491, 611, 840; `tests.nix` 620-629.

## 9. Experiments

| #   | Experiment                                                                                    | Expected result                                                             | What it proves                                   |
| --- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------ |
| E1  | `systemctl --user list-units 'kdn-sway-*' 'dbus-kdn-sway-*'` after a normal exit              | `envs.service` active-exited, `tray.target` active, `sway.service` inactive | stale state exists                               |
| E2  | Same after a crash                                                                            | `sway.service` failed, maybe a pending `envs.service` job                   | start-limit and stale-unit mechanism             |
| E3  | `systemctl --user reset-failed kdn-sway-kdn-sway-sway.service` then start again               | start succeeds or fails on the environment wait                             | separates the start limit from the circular wait |
| E4  | `systemctl --user stop kdn-sway-kdn-sway-envs.service` then start Sway                        | start succeeds                                                              | proves the `envs` circular wait                  |
| E5  | `systemctl status display-manager` after the second exit                                      | "start request repeated too quickly"                                        | proves the DM start limit                        |
| E6  | `systemctl reset-failed display-manager` then restart                                         | restart succeeds                                                            | confirms the start limit                         |
| E7  | SSH login before and after a Sway exit; inspect `env` and `systemctl --user show-environment` | empty variables after the exit                                              | proves the `env-clear` blast radius              |
| E8  | `loginctl list-sessions` and `ls /var/lib/systemd/linger` with an SSH session open            | SSH session has its own session; linger file exists                         | rules out the last-session teardown              |
| E9  | Start Sway from a TTY with `uwsm start -- sway`                                               | session reaches `graphical-session.target`                                  | proves the UWSM path before SDDM                 |
| E10 | `kill -SEGV` under UWSM, then log in again                                                    | login succeeds without a reboot                                             | proves the main goal                             |

## 10. Open questions

1. Does `XDG_CURRENT_DESKTOP` under UWSM come out as `sway:wlroots`, `sway`, or empty? The answer
   decides the portal configuration.
2. Does the SDDM helper exit with status 1 on a normal UWSM logout, or only on an abnormal one?
3. Does any host override `services.dbus.implementation`? The default is already `broker`.
4. Does the repo need `sway-session.target` for any Home Manager service, or can it be disabled?
5. Which host has a spare login for the A/B?
