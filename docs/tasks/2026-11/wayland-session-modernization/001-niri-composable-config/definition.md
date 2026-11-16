---
type: Task
description: Evaluate Niri as a Nix-composable second Wayland session, with full Sway shortcut parity and a UWSM-versus-niri-session decision.
status: open
authored_by: agent
timestamp: 2026-11-16T17:08:00+01:00
---

# Niri evaluation with composable Nix configuration

Parent: [../definition.md](../definition.md)

## Problem

The repo runs Sway as a hand-rolled systemd session. Niri 26.04 is available in the pinned nixpkgs,
and the user wants to evaluate it. The evaluation must answer three questions:

1. Can the Niri KDL be generated from typed Nix options, composed across modules and aspects, and
   validated at build time?
2. Does Niri preserve the current workflow, in particular the current Sway shortcuts?
3. Does UWSM improve the session lifecycle for Niri, or is plain `niri-session` the better fit?

## Goal

A second `niri` or `niri-uwsm` session on one host, selected in SDDM, whose configuration is
generated from a typed `kdn.desktop-niri.*` surface. Sway remains untouched and remains the default
session. The deliverable is a decision, not a migration.

## Non-goals

- Replacing Sway on any host.
- Porting the VNC or headless workflow.
- Reaching parity for features Niri does not have: sticky windows, scratchpad, `layout stacking`,
  `focus parent`, and some swayr commands.
- Changing the Sway session. [002-sway-uwsm-session](../002-sway-uwsm-session/definition.md) owns
  that.
- Extending the universal tree. Niri lands in the den tree only. The universal tree is not grown for
  a new compositor.
- A hand-written `config.kdl` checked into the repo as the primary configuration.

## Hard requirements

1. **Shortcut parity.** Every current Sway binding is represented in Niri or listed in `shortcuts.research.md`
   with a chosen alternative and an explicit accepted loss. The shared key map and the binding
   catalog are the single source of truth. The user signed off on the 9 Sway-specific losses on
   2026-11-16.
2. **Composable Nix.** The configuration is generated from typed options. `niri validate` runs in
   the build. String-templated KDL is an escape hatch only.
3. **Coexistence.** The Niri session does not change Sway's units, environment, portals, or default
   session.
4. **Reversibility.** The Sway session still logs in and behaves exactly as before after the Niri
   work lands.

## Proposed approach

### Phase 0 — inventory and baseline

- Extract every Sway binding into one catalog: `keys.nix`, `home-manager/default.nix`,
  `media-keys.nix`, `swaylock.nix`, `swaync`, `nwg-shell`, `swayr`, `handlr`, `default-secrets`, and
  the host-level binds in `hosts/oams/default.nix`.
- Normalize each entry to `{ chord, flags, action, args, source }`.
- Record the baseline: which binds work in the current session, which are already dead, and which
  are host-specific.

### Phase 1 — typed Niri surface

- Add `modules/den/common/desktop-niri.nix` for the shared key map and the binding catalog.
- Add `modules/den/aspects/desktop-niri.nix` with a `nixos` target and a `homeManager` target.
- Register the new aspect in the den registry at `modules/den/lib.nix`.
- Expose `kdn.desktop-niri.*`: `package`, `keys`, `binds`, `spawnAtStartup`, `windowRules`,
  `outputs`, `workspaces`, `layout`, `input`, `animations`, `environment`, `extraKdl`,
  `useNautilus`, `session` (`niri-session` or `uwsm`), and the portal policy.
- Render to `wayland.windowManager.niri.settings` and `extraConfig`. Keep every repeated node as a
  `_children` list. Keep window-rule, output, and workspace order in lists. Enforce one definition
  site per list.
- Set `checkConfig = true` so `niri validate` gates the build.

The option tree and the rendering rules are in [design.md](design.md).

### Phase 2 — minimal session spike

- Start with `programs.niri.enable = true` and `wayland.windowManager.niri.enable = true`, with no
  UWSM.
- Log in from SDDM as the second session.
- Prove `graphical-session.target`, `niri msg outputs`, portals, waybar, swaync, swaylock and
  swayidle, screenshots, and XWayland.
- Record every deviation from Sway in `shortcuts.research.md`.

### Phase 3 — shortcut parity

- Generate the Niri `binds` from the catalog. Apply these mappings:
  - `--locked` becomes `allow-when-locked=true`.
  - `--inhibited` becomes `allow-inhibiting=false`.
  - `--release` becomes a press bind with `repeat=false`. Niri 26.04 has no release-triggered binds,
    and the existing `ydotool-paste` sleep covers the release.
  - The resize mode becomes direct chords that call `set-column-width`, `set-window-height`, and the
    preset actions.
  - The passthrough mode becomes `toggle-keyboard-shortcuts-inhibit`.
  - swayr becomes `recent-windows`, `focus-window-previous`, `close-window`, and
    `niri msg pick-window`.
  - The static workspaces become named workspaces or `focus-workspace N`.
  - The lid switch becomes native Niri behaviour.
  - Media keys use `allow-when-locked=true`.
  - Host keys remain external commands, except the output toggle, which becomes a short
    `niri msg output` script.
- Run the parity checklist live, key by key, and record pass, alternative, or loss.

### Phase 4 — UWSM A/B

- Add `programs.uwsm` and a `niri-uwsm` session. Keep the plain `niri` session as the control.
- Compare these criteria:
  - login reaches `graphical-session.target`;
  - `WAYLAND_DISPLAY`, `DISPLAY`, `NIRI_SOCKET`, and `XDG_CURRENT_DESKTOP` reach the user manager;
  - portals and screencast work;
  - logout stops the session units in order and leaves no stale state;
  - a crash is followed by a new login without a reboot;
  - XDG autostart runs exactly once;
  - applications land in the intended slices;
  - `uwsm finalize NIRI_SOCKET` is or is not required;
  - `niri-session` under UWSM does not act as a second session manager;
  - the number of custom units stays at zero.
- Use the scorecard in [design.md](design.md). Do not flip the default session.

### Phase 5 — decision

- Write `done.md`, or `status.md` if the task is parked, with a clear recommendation: keep Niri as a
  second session, migrate one host, adopt UWSM, or drop Niri.
- Record the exact gaps and the conditions that would change the decision.

## Deliverables

| File                    | Contents                                                                                                       |
| ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| `research.md`           | Niri module analysis, KDL composability, session and portal behaviour, feature gaps.                           |
| `design.md`             | Typed option tree, rendering rules, shortcut parity mechanism, UWSM scorecard.                                 |
| `shortcuts.research.md` | One row per current binding: Niri chord and action, parity, alternative, accepted loss.                        |
| Nix changes             | `modules/den/common/desktop-niri.nix`, `modules/den/aspects/desktop-niri.nix`, and an optional host inclusion. |
| Checks                  | `niri validate` in the build, a den assertion set for the new aspect, and a shortcut-coverage assertion.       |
| `done.md`               | The evaluation result and the recommendation.                                                                  |

## Acceptance criteria

- [ ] The relevant `nix build .#checks.<system>.…` bundle passes.
- [ ] `niri validate -c <generated config>` passes as part of the build.
- [ ] The Niri session and the Sway session both log in from SDDM on the test host.
- [ ] `systemctl --user show-environment` in the Niri session contains `WAYLAND_DISPLAY`, `DISPLAY`,
      `NIRI_SOCKET`, and `XDG_CURRENT_DESKTOP`.
- [ ] Every binding in the inventory has a `shortcuts.research.md` row: reproduced, alternative, or accepted loss.
      The 9 accepted losses are signed off as of 2026-11-16.
- [ ] Waybar, swaync, swaylock and swayidle, screenshots, XWayland, and portals are exercised and
      recorded.
- [ ] Sway still logs in and every Sway binding still works after the Niri change lands.
- [ ] The UWSM A/B is complete and the recommendation is recorded.

## Risks

- `wayland.windowManager.niri.settings` is a free-form `attrsOf`, not a typed niri schema. A typo is
  caught only by `niri validate`, and the build is the feedback loop.
- `listOf` values concatenate across module definitions. Two definitions of one `spawn` silently
  become two arguments.
- `window-rule`, `output`, and `workspace` order is semantic. The generator sorts plain attributes
  alphabetically, so these must be `_children` lists.
- Niri hardcodes `XDG_CURRENT_DESKTOP=niri`. A custom session name cannot select its own portal
  configuration, and the `kdn-` naming convention cannot carry over verbatim.
- `environment {}` in KDL does not reach the systemd user manager. A wrong carrier silently degrades
  Electron and Qt applications.
- `GDK_BACKEND=wayland` must not be exported in a Niri session. It breaks the screencast portal.
- Niri has no headless or virtual output. The `sway-vnc` headless workflow does not port.
- Niri issue #2435 (logout ordering) is open. A quit-bound `niri-shutdown.target` or UWSM is the
  mitigation.
- The Secret Service conflict remains: `programs.niri` points the portal at `gnome-keyring`, while the
  repo runs rosec or KeePassXC as `org.freedesktop.secrets`.

## Open questions

1. Is the evaluation host `oams`, which has host-specific keys, or a simpler host?
2. Is plain `niri-session` or `niri-uwsm` the first spike?
3. Are workspaces named `"1".."10"`, or dynamic with index binds?

## Resolved decisions

- 2026-11-16: the user accepted the 9 Sway-specific losses. They are the `accepted-loss` rows in
  `shortcuts.research.md`. Scratchpad is not bound in the current Sway config, so it is not one of
  the 9.
