---
type: Task
description: Evaluate Niri with a Nix-composable configuration and move the Sway session onto UWSM, keeping every current Sway shortcut.
status: open
authored_by: agent
timestamp: 2026-11-16T17:05:00+01:00
---

# Wayland session modernization

This umbrella holds two tasks that share one decision: how a graphical session starts, receives its
environment, and tears down on this repository's NixOS hosts.

## Why one family

Both tasks touch the same session layer: SDDM (`services.displayManager`), `programs.sway` /
`programs.niri`, the custom `kdn-sway-kdn-sway-*` systemd graph, `wayland.systemd.target`, the XDG
portal configuration, the polkit agent, and the `org.freedesktop.secrets` shim. A UWSM decision made
for Sway must be the same decision made for Niri. Two different session models would double the
maintenance and the failure modes.

Both tasks also share one product constraint: **the current Sway shortcuts must survive**. The user
relies on them. A compositor or session change that silently drops a binding is a regression, not an
acceptable trade-off.

## Sub-tasks

| #   | Task                                                                                 | Purpose                                                                                                                              |
| --- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| 001 | [001-niri-composable-config/definition.md](001-niri-composable-config/definition.md) | Evaluate Niri as a second session whose configuration is generated from typed Nix options, with shortcut parity and a UWSM A/B.      |
| 002 | [002-sway-uwsm-session/definition.md](002-sway-uwsm-session/definition.md)           | Replace the hand-rolled Sway session graph with UWSM, so a compositor exit or crash can be followed by a new login without a reboot. |

## Shared evidence

[research.md](research.md) holds the evidence both tasks rely on: the pinned versions, the current
session graph, the root causes of the four recorded Sway symptoms, the UWSM model, and the
shortcut inventory.

## Ordering

1. **002 first, as an A/B.** Add a UWSM-managed `sway-uwsm` session beside the existing `kdn-sway`
   session. The greeter then offers both, so the change is reversible without a rebuild. Do not flip
   `defaultSession` until the symptoms are reproduced and cleared.
2. **001 in parallel, isolated.** The Niri evaluation is a second session. It must not edit the Sway
   tree. It consumes the shared session decision from 002 once that decision exists. Until then, it
   uses plain `niri-session` as its control.
3. **Choose once.** After both spikes, record one session model in this umbrella. If UWSM wins, both
   compositors use it. If plain `niri-session` wins for Niri, record why Sway still needs UWSM or why
   it does not.

## Hard constraints

- **Shortcut preservation.** Every binding the repo configures today must be either reproduced in
  Niri or recorded in the parity table with an explicit alternative and the user's sign-off. No
  silent drops. The shared key map stays the single source of truth. The user signed off on the 9
  Sway-specific losses on 2026-11-16.
- **Both trees stay in sync.** `modules/universal/**` and `modules/den/**` duplicate the Sway session
  today. Any session change lands in both, and the den assertions are updated in the same change.
- **No agent activation.** The agent evaluates and builds. The user runs `switch`, logs in, and judges
  the desktop.
- **No hand-written KDL as the primary source.** Niri configuration is generated from typed Nix
  options. Raw KDL is an escape hatch, not the main surface.
- **Keep the existing Sway behaviour while both sessions coexist.** A second session must not alter
  the first one's environment, portals, or unit graph.

## Decisions needed

1. UWSM for Sway only, for both compositors, or for neither?
2. Does Niri replace Sway on a host, coexist on every host, or stay an evaluation-only session?
3. What is the canonical session name per compositor (`sway`, `sway-uwsm`, `niri`, `niri-uwsm`)?
   The portal configuration is selected by `XDG_CURRENT_DESKTOP`, so this is not cosmetic.
4. How is the Secret Service resolved? `programs.niri` defaults the portal to `gnome-keyring`, while
   the repo runs its own `org.freedesktop.secrets` unit for rosec or KeePassXC.
5. ~~Which Sway-only workflows may disappear (sticky, scratchpad, `layout stacking`, `focus parent`,
   swayr commands), and which need a replacement?~~ Resolved 2026-11-16: the 9 Sway-specific
   bindings are accepted as losses. See
   [001-niri-composable-config/shortcuts.research.md](001-niri-composable-config/shortcuts.research.md).

## Done when

- Both sub-tasks are `done`, or one is explicitly dropped with a recorded decision.
- One session model is recorded and applied to both trees.
- The Sway shortcuts are proven equal before and after the session change.
- A Niri session either exists as a supported second session, or the evaluation produced a recorded
  "no" with reasons.
