---
type: Research
description: Shared evidence for the Niri evaluation and the Sway-to-UWSM migration, including pinned versions, the current session graph, root causes, and the shortcut inventory.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T17:06:00+01:00
---

# Shared research: Wayland session modernization

This file holds the evidence that both sub-tasks use. Sub-task-specific findings live in
[001-niri-composable-config/research.md](001-niri-composable-config/research.md) and
[002-sway-uwsm-session/research.md](002-sway-uwsm-session/research.md).

## 1. Pinned versions

| Input        | Revision or version                        | Evidence                                                                      |
| ------------ | ------------------------------------------ | ----------------------------------------------------------------------------- |
| nixpkgs      | `319e4cebef10cbb636c6ea392137b52ad105336a` | `flake.lock`; store path `/nix/store/lk98r48k05nwda8yh4fzyd9bn6l5z02m-source` |
| home-manager | `a9752a621164e9f84eb2a15858f1d54fd3cedab8` | `flake.lock`; store path `/nix/store/g2pw16iw5lz58xjyhv529l27asny52pl-source` |
| niri         | `26.04`                                    | `<nixpkgs>/pkgs/by-name/ni/niri/package.nix:30`                               |
| uwsm         | `0.27.1`                                   | `<nixpkgs>/pkgs/by-name/uw/uwsm/package.nix:32`                               |

Both compositors have first-class modules in the pin:

- NixOS: `programs.niri` at `<nixpkgs>/nixos/modules/programs/wayland/niri.nix` and
  `programs.uwsm` at `<nixpkgs>/nixos/modules/programs/wayland/uwsm.nix`.
- Home Manager: `wayland.windowManager.niri` at
  `<home-manager>/modules/services/window-managers/niri.nix`, with `settings`, `extraConfig`,
  `checkConfig`, `systemd.enable`, `xwaylandSatellitePackage`, and `portalPackage`.

> **Correction:** one deep-dive review reported that the pinned Home Manager has no niri module.
> A direct `ls` and `rg` of the pinned store path proves that it does. The review used the wrong
> conclusion. The module exists and is the intended configuration surface.

## 2. The current Sway session in one picture

The session is a hand-rolled UWSM. SDDM does not start the compositor. It starts a shell script,
which asks the user manager to start the compositor:

```
SDDM -> kdn-sway-start --wait --ignore-error
      -> systemctl --user start kdn-sway-kdn-sway-sway.service
      -> sway (inside user@UID.service, outside the logind session scope)
```

The custom graph:

```
kdn-sway-kdn-sway-sway.service      Type=notify, NotifyAccess=all, Slice=session.slice,
                                    BindsTo graphical-session.target + session.target,
                                    ExecStopPost = env-clear, Restart=no
kdn-sway-kdn-sway-session.target    BindsTo graphical-session.target + sway.service,
                                    Requires envs.target + tray.target
kdn-sway-kdn-sway-envs.service      oneshot, RemainAfterExit=true,
                                    ExecStart = env-wait; sleep 2; echo
kdn-sway-kdn-sway-envs.target       PartOf session.target, BindsTo envs.service
kdn-sway-kdn-sway-tray.target       BindsTo tray.target, Requires envs.target
dbus-kdn-sway-secrets-service.*     Type=dbus, BusName=org.freedesktop.secrets
kdn-sway-kdn-sway-polkit-agent.*    PartOf session.target, Requires envs.target
xdg-desktop-portal{,-gtk}           PartOf session.target, Requires envs.target
gpg-agent                           PartOf + StopPropagatedFrom envs.target
```

Sources: `modules/universal/desktop/sway/default.nix:258-369`, `:497-563`;
`modules/universal/desktop/sway/bundle.nix:11-167`; den port at
`modules/den/aspects/desktop-sway.nix:682-970`.

The environment handoff has two phases:

1. `kdn-sway-start` runs `env-clear`, then `env-load`. `env-clear` unsets every variable in the user
   manager and empties it on the session bus. `env-load` imports the whole SDDM environment.
2. Inside the compositor, `/etc/sway/config.d/00-kdn-sway-init.conf` runs `env-load` again with
   `WAYLAND_DISPLAY`, then sends `READY=1` through a renamed `NOTIFY_SOCKET`.

`envs.service` polls until `WAYLAND_DISPLAY` and `KDN_SWAY_SYSTEMD` appear. Every session service is
ordered after that barrier.

## 3. Root causes of the four recorded symptoms

The TODOs are at `modules/universal/desktop/sway/default.nix:14-16` and
`modules/den/aspects/desktop-sway.nix:601-603`. The full unit audit is in
[002-sway-uwsm-session/research.md](002-sway-uwsm-session/research.md).

| Symptom                                                                         | Most likely cause                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Confidence                                   |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| Exiting Sway does not stop or restart `sddm-helper` / `display-manager.service` | SDDM treats a helper exit with status 1 as an authentication error and deliberately does not restart the greeter (`sddm#1908`). Separately, `kdn-sway-start` returns only after `sway.service` reaches inactive or failed, so a start notification lost in a `set -e` script can leave the unit in `activating` for up to `TimeoutStartSec=300`.                                                                                                                                                                                  | Medium-high                                  |
| A second exit cannot `systemctl restart display-manager.service`                | `display-manager.service` has `Restart=always`, `StartLimitBurst=3`, and `StartLimitIntervalSec=30`. Repeated exits trip the start limit, and even a manual start is refused until `systemctl reset-failed display-manager.service`.                                                                                                                                                                                                                                                                                              | High                                         |
| After a crash, Sway needs a reboot                                              | The custom graph has no shutdown contract. `envs.service` stays `active (exited)` because it has no `PartOf` and no `StopWhenUnneeded`. `sway.service` stays `failed` because `Restart=no` and nothing calls `reset-failed`. Failed units stay loaded because no unit sets `CollectMode`. The next start can wait forever on `envs.service`, whose oneshot has no `TimeoutStartSec`, while `env-wait` waits for variables that only a successful Sway start produces. Lingering keeps the stale user manager alive across logins. | High                                         |
| Exiting Sway logs out all SSH sessions                                          | Not reproduced in code review. `KillUserProcesses=false`, lingering is on, and nothing calls `loginctl terminate-user`. The strongest candidate is `env-clear`: it empties every variable on the shared session bus and in the user manager, so later D-Bus activations and user units inherit empty `PATH`, `HOME`, `XDG_RUNTIME_DIR`, and `DBUS_SESSION_BUS_ADDRESS`. The second candidate is that SSH logins were children of the Sway session.                                                                                | Medium for the env cause; needs a live repro |

The common defect is structural: the compositor is a proxy-started process outside the logind
session, and the custom graph has no `wayland-session-shutdown`-style target. The custom units also
do not use `PropagatesStopTo` or `CollectMode`.

## 4. The UWSM model

UWSM is a set of templated systemd user units plus a launcher. It does not run a daemon. The units
that matter:

| Unit                                    | Role                                                                                                                     |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `wayland-session-pre@.target`           | binds `wayland-wm-env@.service` to `graphical-session-pre.target`                                                        |
| `wayland-wm-env@.service`               | oneshot preloader; exports only the environment delta to systemd and D-Bus; records it for cleanup                       |
| `wayland-session@.target`               | binds the compositor to `graphical-session.target` with `BindsTo` and `PropagatesStopTo`                                 |
| `wayland-wm@.service`                   | the compositor; `Type=notify`, `OnSuccess`/`OnFailure=wayland-session-shutdown.target`, `CollectMode=inactive-or-failed` |
| `wayland-session-waitenv.service`       | waits for `WAYLAND_DISPLAY` (30 s timeout, `OnFailure` shutdown)                                                         |
| `wayland-session-shutdown.target`       | `Conflicts=graphical-session-pre.target graphical-session.target xdg-desktop-autostart.target`                           |
| `wayland-session-bindpid@.service`      | binds the login session to the graphical session                                                                         |
| `wayland-session-xdg-autostart@.target` | runs XDG autostart, which the current session never does                                                                 |

Under UWSM, a compositor exit or crash stops the whole session graph in order, and a new login can
reach `graphical-session.target` again. UWSM does **not** restart the compositor in place.
"Restart" means "log in again", which now works without a reboot.

UWSM also provides `uwsm app --`, which places applications in `app-graphical.slice`,
`background-graphical.slice`, or `session-graphical.slice`. The current session has no per-session
process cleanup because `KillUserProcesses=false`.

Two constraints apply:

- `programs.uwsm.enable` sets `services.dbus.implementation = "broker"` with a plain assignment. The
  nixpkgs default is already `broker`, so this only conflicts with a host that sets `"dbus"`.
- `waylandCompositors.<name>` generates a `<name>-uwsm.desktop` entry with
  `Exec=uwsm start -F -- <binPath> <extraArgs>` and no `DesktopNames`. Portal selection depends on
  `XDG_CURRENT_DESKTOP`, so this gap needs a live check.

## 5. Niri configuration surface

The NixOS module is thin. It enables the package, installs the package's own
`niri.desktop`/`niri.service`/`niri-shutdown.target`, sets `defaultSession = lib.mkDefault "niri"`,
enables gnome-keyring, configures `xdg.portal.config.niri` with `gnome` and `gtk`, and adds
`xdg-desktop-portal-gnome` for screencast. It does **not** install `xwayland-satellite`.

The Home Manager module is the composition surface:

| Option                                           | Behaviour                                                         |
| ------------------------------------------------ | ----------------------------------------------------------------- |
| `wayland.windowManager.niri.settings`            | `attrsOf valueType`, rendered to KDL by `lib.hm.generators.toKDL` |
| `wayland.windowManager.niri.extraConfig`         | raw KDL lines, appended at `mkOrder 999`                          |
| `wayland.windowManager.niri.enableDefaultConfig` | emits `include "<package>/resources/default-config.kdl"`          |
| `wayland.windowManager.niri.checkConfig`         | runs `niri validate --config <file>` in the build                 |
| `wayland.windowManager.niri.package`             | nullable; `null` disables validation                              |
| `wayland.windowManager.niri.systemd.enable`      | installs the package's units; default `true`                      |

The generator is not a niri schema. It is a generic KDL writer. Three traps follow:

1. A list of attribute sets becomes `-` children, which niri rejects. Repeated nodes must use
   `_children`.
2. Plain attributes are emitted in alphabetical order. Window-rule order is semantic, so rules must
   be an ordered `_children` list.
3. `listOf` values concatenate across module definitions. Two definitions of one `spawn` become two
   arguments, not an override.

A fourth trap is cross-file: `include` is positional, and multipart sections (`window-rule`,
`output`, `workspace`) are inserted as-is and never merged.

Niri-specific session facts:

- `niri.service` has `BindsTo=graphical-session.target`, `Before=graphical-session.target`,
  `Type=notify`, and `Slice=session.slice`.
- `niri-session` imports the environment, starts `niri.service`, then starts
  `niri-shutdown.target` after the compositor exits.
- Niri hardcodes `XDG_CURRENT_DESKTOP=niri`. A custom session name cannot select a custom portal
  configuration.
- `environment {}` in KDL reaches niri's children only. It does not reach the systemd user manager.
- `GDK_BACKEND` must not be set globally in a niri session. It breaks the screencast portal.
- Niri issue #2435 (logout ordering) is open. A quit-bound `niri-shutdown.target` or UWSM mitigates
  it.

## 6. Shortcut inventory

The shortcuts are spread over many files. This is the inventory that the Niri parity table must
cover:

| Source                                                              | Bindings                                                                                                                                                                 |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `modules/universal/desktop/sway/keys.nix`                           | the 13 friendly modifier and key names                                                                                                                                   |
| `modules/universal/desktop/sway/home-manager/default.nix:127-212`   | core binds: paste, kill, wlogout, file manager, calculator, terminal, launcher, wofi, layout, fullscreen, floating, sticky, modes, focus, move, outputs, workspaces 1–10 |
| `modules/universal/desktop/sway/home-manager/default.nix:214-248`   | `mode resize` ladder and `mode passthrough`                                                                                                                              |
| `modules/universal/desktop/sway/home-manager/media-keys.nix`        | brightness, volume, mute, mic mute, `--locked` media keys, `Print` and `--inhibited Super+Print`                                                                         |
| `modules/universal/desktop/sway/home-manager/swaylock.nix`          | `Super+L` lock                                                                                                                                                           |
| `modules/universal/desktop/sway/home-manager/swaync/default.nix`    | `Super+N` notification centre                                                                                                                                            |
| `modules/universal/desktop/sway/home-manager/nwg-shell/default.nix` | `Super+P` display editor                                                                                                                                                 |
| `modules/universal/desktop/sway/home-manager/swayr.nix`             | eight swayr binds: `Super+Space`, `Super+Delete`, `Super+Tab`, `Alt+Tab`, `Alt+Shift+Tab`, `Super+Shift+Space`, `Super+C`, `Super+Shift+C`                               |
| `modules/universal/programs/handlr/default.nix`                     | `Super+O` open clipboard                                                                                                                                                 |
| `modules/universal/profile/default-secrets/default.nix`             | `Ctrl+Super+A` anonymise clipboard                                                                                                                                       |
| `hosts/oams/default.nix:250-259`                                    | `XF86Launch4`, `XF86Launch1`, `XF86KbdBrightnessDown/Up`, `Shift+Super+P` output toggle                                                                                  |
| `modules/universal/desktop/sway/home-manager/default.nix:107-108`   | lid close/open output disable and enable                                                                                                                                 |

Niri has no release-triggered binds, no keybinding modes, and no Sway container tree. The following
binds need an explicit alternative or an accepted loss. The 9 accepted losses are Sway-specific and
were signed off on 2026-11-16; the authoritative list is in
[001-niri-composable-config/shortcuts.research.md](001-niri-composable-config/shortcuts.research.md).

| Sway bind                                                 | Niri status                                                                                                               |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `--release Super+V`, `--inhibited --release Super+Ctrl+V` | no release binds; use a press bind with `repeat=false`; the existing `ydotool-paste` sleep covers the release             |
| `Super+R` + resize ladder                                 | no modes; map the same chords to `set-column-width`, `set-window-height`, `switch-preset-column-width`                    |
| `Super+Pause`, `Super+Scroll_Lock` passthrough            | use `toggle-keyboard-shortcuts-inhibit`                                                                                   |
| `Super+Ctrl+S` layout stacking                            | no equivalent                                                                                                             |
| `Super+Ctrl+E` layout toggle split                        | no equivalent                                                                                                             |
| `Super+Shift+S` sticky                                    | no equivalent (`niri#932`)                                                                                                |
| `Super+A` focus parent                                    | no equivalent                                                                                                             |
| `Super+Shift+mouse-up/down` focus next/prev sibling       | no equivalent                                                                                                             |
| `Super+Space` and other swayr binds                       | `recent-windows`, `focus-window-previous`, `close-window`, `niri msg pick-window`; some swayr commands have no equivalent |
| `Super+1..0` static workspaces                            | `focus-workspace N` or named workspaces `"1".."10"`; index binds stop at the last workspace                               |
| `Super+Shift+P` output toggle                             | needs a short `niri msg output` script                                                                                    |
| `XF86TouchpadToggle`                                      | no runtime toggle action                                                                                                  |

Media keys, `--locked` binds, `--inhibited` binds, external commands, waybar, swaync, swaylock,
swayidle, grim, slurp, wf-recorder, kanshi, gammastep, wl-clipboard, ydotool, wofi, nwg-drawer,
handlr, foot, nemo, and qalculate-qt are expected to work with little or no change. The full matrix
is in [001-niri-composable-config/research.md](001-niri-composable-config/research.md).

## 7. Cross-cutting constraints

| Topic                    | Constraint                                                                                                                                                                                                                                        |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Portal selection         | `xdg.portal.config.<name>` is selected by `XDG_CURRENT_DESKTOP`. Niri hardcodes `niri`; UWSM sets it from `DesktopNames`, `-D`, or the compositor basename. A custom `kdn-` session name does not control it.                                     |
| Secret Service           | The repo runs its own `org.freedesktop.secrets` unit for rosec or KeePassXC. `programs.niri` defaults the portal to `gnome-keyring`. The Niri aspect must choose one owner.                                                                       |
| `xdg.portal.config.sway` | nixpkgs already writes the same five keys for every `programs.sway` host. The repo repeats them. The option merges with `mergeEqualOption`, so any future divergence becomes a hard evaluation error. The Niri port must not repeat this pattern. |
| dbus                     | UWSM assigns `services.dbus.implementation = "broker"` at plain priority. The nixpkgs default is already `broker`, so this is a no-op unless a host overrides it.                                                                                 |
| Lingering                | `users.users.kdn.linger = true` keeps the user manager alive across logins. That is good for UWSM, but it also keeps stale units alive. UWSM's `CollectMode` and shutdown target are what make it safe.                                           |
| XDG autostart            | The current session never starts `xdg-desktop-autostart.target`. UWSM does. Expect new autostarted applications after the migration, and check for duplicates with `dex`.                                                                         |
| SDDM                     | SDDM forks the session `Exec=` and treats a helper exit with status 1 as an authentication error (`sddm#1908`). UWSM fixes the session side, not this SDDM behaviour.                                                                             |
| Doubled prefix           | The live unit names carry `kdn-sway` twice (`kdn-sway-kdn-sway-…`). The den checks pin them. A rename is a migration, not a refactor.                                                                                                             |

## 8. Open questions

1. Which host is the test host for both tasks? It needs SDDM, Sway, a spare login, and ideally the
   host-specific `oams` keys.
2. Does the SSH-logout symptom reproduce? If not, close it as "not reproducible" with the collected
   evidence and keep the `env-clear` blast radius as the working explanation.
3. Does any host override `services.dbus.implementation`? The nixpkgs default is already `broker`, so
   the UWSM assignment is a no-op unless a host sets `"dbus"`.
4. Does `XDG_CURRENT_DESKTOP` come out as `sway:wlroots` under UWSM with the generated entry, or as
   plain `sway`? This decides the portal configuration.

Resolved: the user accepted the 9 Sway-specific losses on 2026-11-16. They are the `accepted-loss`
rows in [001-niri-composable-config/shortcuts.research.md](001-niri-composable-config/shortcuts.research.md).
