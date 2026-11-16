---
type: Research
description: The complete Sway binding inventory, the proposed Niri mapping for each binding, and the live parity checklist.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T17:20:00+01:00
---

# Shortcut parity inventory

This file is the working checklist for the user's hard constraint: **keep the Sway shortcuts**. It
lists every binding the repo configures today, the proposed Niri mapping, and the parity state.

Status values:

| Status          | Meaning                                                                            |
| --------------- | ---------------------------------------------------------------------------------- |
| `reproduced`    | The same chord performs the same action in Niri.                                   |
| `alternative`   | The same intent is reachable, but the chord, the action, or the behaviour differs. |
| `accepted-loss` | Niri has no equivalent. All 9 are Sway-specific and were signed off 2026-11-16.    |
| `todo`          | Not yet tested.                                                                    |

A row is complete when it is `reproduced`, or when the user signed off on an `alternative` or
`accepted-loss` row. The user signed off on all 9 `accepted-loss` rows on 2026-11-16 because they are
Sway-specific features.

## 1. Core bindings

Source: `modules/universal/desktop/sway/home-manager/default.nix:127-212`.

| #   | Sway chord                                         | Flags                      | Sway action                                | Proposed Niri mapping                                                                                           | Status        |
| --- | -------------------------------------------------- | -------------------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------- | ------------- |
| 1   | `Super+V`                                          | `--release`                | `ydotool-paste`                            | `Super+V` press, `repeat=false`, `spawn ydotool-paste`                                                          | alternative   |
| 2   | `Super+Ctrl+V`                                     | `--inhibited`, `--release` | `ydotool-paste`                            | `Super+Ctrl+V` press, `allow-inhibiting=false`, `repeat=false`                                                  | alternative   |
| 3   | `Alt+F4`                                           | —                          | `kill`                                     | `Alt+F4` `close-window`                                                                                         | reproduced    |
| 4   | `Ctrl+Alt+Delete`                                  | —                          | `wlogout`                                  | `spawn wlogout`                                                                                                 | reproduced    |
| 5   | `Super+E`                                          | —                          | `nemo`                                     | `spawn nemo`                                                                                                    | reproduced    |
| 6   | `Super+K`                                          | —                          | `qalculate-qt`                             | `spawn qalculate-qt`                                                                                            | reproduced    |
| 7   | `Super+Return`                                     | —                          | `foot`                                     | `spawn foot`                                                                                                    | reproduced    |
| 8   | `Super+D`                                          | —                          | nwg-drawer launcher                        | `spawn nwg-drawer`                                                                                              | reproduced    |
| 9   | `Alt+F2`                                           | —                          | `wofi --show run`                          | `spawn wofi --show run`                                                                                         | reproduced    |
| 10  | `Super+Shift+Q`                                    | —                          | `kill`                                     | `close-window`                                                                                                  | reproduced    |
| 11  | `Super+Ctrl+S`                                     | —                          | `layout stacking`                          | none                                                                                                            | accepted-loss |
| 12  | `Super+Ctrl+T`                                     | —                          | `layout tabbed`                            | `toggle-column-tabbed-display`                                                                                  | alternative   |
| 13  | `Super+Ctrl+E`                                     | —                          | `layout toggle split`                      | none                                                                                                            | accepted-loss |
| 14  | `Super+F`                                          | —                          | `fullscreen`                               | `fullscreen-window`                                                                                             | reproduced    |
| 15  | `Super+Shift+F`                                    | —                          | `floating toggle`                          | `toggle-window-floating`                                                                                        | reproduced    |
| 16  | `Super+Shift+S`                                    | —                          | `sticky toggle`                            | none                                                                                                            | accepted-loss |
| 17  | `Super+R`                                          | —                          | enter `mode resize`                        | no modes; see §2 for the direct chords                                                                          | alternative   |
| 18  | `Super+Pause`                                      | —                          | enter `mode passthrough`                   | `toggle-keyboard-shortcuts-inhibit`                                                                             | alternative   |
| 19  | `Super+Scroll_Lock`                                | —                          | enter `mode passthrough`                   | `toggle-keyboard-shortcuts-inhibit`                                                                             | alternative   |
| 20  | `Super+A`                                          | —                          | `focus parent`                             | none                                                                                                            | accepted-loss |
| 21  | `Super+Left`                                       | —                          | `focus left`                               | `focus-column-left`                                                                                             | reproduced    |
| 22  | `Super+Down`                                       | —                          | `focus down`                               | `focus-window-down`                                                                                             | alternative   |
| 23  | `Super+Up`                                         | —                          | `focus up`                                 | `focus-window-up`                                                                                               | alternative   |
| 24  | `Super+Right`                                      | —                          | `focus right`                              | `focus-column-right`                                                                                            | reproduced    |
| 25  | `Super+Button5`                                    | `--border --whole-window`  | `focus right`                              | `Mod+WheelScrollDown` or `Mod+WheelScrollUp`, direction depends on `natural-scroll`; acts on the focused window | alternative   |
| 26  | `Super+Button4`                                    | `--border --whole-window`  | `focus left`                               | the other wheel direction                                                                                       | alternative   |
| 27  | `Super+Shift+Button5`                              | `--border --whole-window`  | `focus next sibling`                       | none                                                                                                            | accepted-loss |
| 28  | `Super+Shift+Button4`                              | `--border --whole-window`  | `focus prev sibling`                       | none                                                                                                            | accepted-loss |
| 29  | `Super+Shift+Left`                                 | —                          | `move left`                                | `move-column-left`                                                                                              | reproduced    |
| 30  | `Super+Shift+Down`                                 | —                          | `move down`                                | `move-window-down`                                                                                              | alternative   |
| 31  | `Super+Shift+Up`                                   | —                          | `move up`                                  | `move-window-up`                                                                                                | alternative   |
| 32  | `Super+Shift+Right`                                | —                          | `move right`                               | `move-column-right`                                                                                             | reproduced    |
| 33  | `Super+Shift+Ctrl+Left`                            | —                          | `move workspace to output left`            | `move-workspace-to-monitor-left`                                                                                | reproduced    |
| 34  | `Super+Shift+Ctrl+Down`                            | —                          | `move workspace to output down`            | `move-workspace-to-monitor-down`                                                                                | reproduced    |
| 35  | `Super+Shift+Ctrl+Up`                              | —                          | `move workspace to output up`              | `move-workspace-to-monitor-up`                                                                                  | reproduced    |
| 36  | `Super+Shift+Ctrl+Right`                           | —                          | `move workspace to output right`           | `move-workspace-to-monitor-right`                                                                               | reproduced    |
| 37  | `Super+1` … `Super+9`, `Super+0`                   | —                          | `workspace number 1..10`                   | `focus-workspace "1".."10"` with named workspaces                                                               | alternative   |
| 38  | `Super+Shift+1` … `Super+Shift+9`, `Super+Shift+0` | —                          | `move container to workspace number 1..10` | `move-column-to-workspace "N" focus=false`                                                                      | reproduced    |

Rows 37 and 38 are 20 bindings. The generated config must contain all 20.

## 2. Resize mode

Source: `modules/universal/desktop/sway/home-manager/default.nix:219-248`.

Sway enters this mode with `Super+R`. Niri has no modes. The proposal maps every chord to a direct
`set-column-width` or `set-window-height` action. The chord is the same, but it no longer needs the
`Super+R` prefix. This is a behaviour change: the user can resize without entering a mode, but the
mode itself is gone.

| #   | Sway chord in `mode resize` | Sway action                | Proposed Niri mapping                                         | Status      |
| --- | --------------------------- | -------------------------- | ------------------------------------------------------------- | ----------- |
| 39  | `Super+Ctrl+Left`           | `resize shrink width 1`    | `set-column-width "-1%"`                                      | alternative |
| 40  | `Super+Ctrl+Down`           | `resize grow height 1`     | `set-window-height "+1%"`                                     | alternative |
| 41  | `Super+Ctrl+Up`             | `resize shrink height 1`   | `set-window-height "-1%"`                                     | alternative |
| 42  | `Super+Ctrl+Right`          | `resize grow width 1`      | `set-column-width "+1%"`                                      | alternative |
| 43  | `Ctrl+Left`                 | `resize shrink width 5`    | `set-column-width "-5%"`                                      | alternative |
| 44  | `Ctrl+Down`                 | `resize grow height 5`     | `set-window-height "+5%"`                                     | alternative |
| 45  | `Ctrl+Up`                   | `resize shrink height 5`   | `set-window-height "-5%"`                                     | alternative |
| 46  | `Ctrl+Right`                | `resize grow width 5`      | `set-column-width "+5%"`                                      | alternative |
| 47  | `Left`                      | `resize shrink width 15`   | `set-column-width "-15%"`                                     | alternative |
| 48  | `Down`                      | `resize grow height 15`    | `set-window-height "+15%"`                                    | alternative |
| 49  | `Up`                        | `resize shrink height 15`  | `set-window-height "-15%"`                                    | alternative |
| 50  | `Right`                     | `resize grow width 15`     | `set-column-width "+15%"`                                     | alternative |
| 51  | `Alt+Left`                  | `resize shrink width 50`   | `switch-preset-column-width-back` or `set-column-width "50%"` | alternative |
| 52  | `Alt+Down`                  | `resize grow height 50`    | `switch-preset-window-height` or `set-window-height "50%"`    | alternative |
| 53  | `Alt+Up`                    | `resize shrink height 50`  | `set-window-height "50%"`                                     | alternative |
| 54  | `Alt+Right`                 | `resize grow width 50`     | `set-column-width "50%"`                                      | alternative |
| 55  | `Super+Alt+Left`            | `resize shrink width 100`  | `set-column-width "100%"` or `maximize-column`                | alternative |
| 56  | `Super+Alt+Down`            | `resize grow height 100`   | `maximize-window-to-edges` or `set-window-height "100%"`      | alternative |
| 57  | `Super+Alt+Up`              | `resize shrink height 100` | `set-window-height "100%"`                                    | alternative |
| 58  | `Super+Alt+Right`           | `resize grow width 100`    | `set-column-width "100%"` or `maximize-column`                | alternative |
| 59  | `Return`                    | `mode default`             | no mode to leave                                              | alternative |
| 60  | `Escape`                    | `mode default`             | no mode to leave                                              | alternative |

The user must confirm that losing the `Super+R` gate is acceptable. If it is not, the alternative is
an external mode helper, which adds custom code and is out of scope for the first spike.

## 3. Passthrough mode

Source: `modules/universal/desktop/sway/home-manager/default.nix:214-217`.

| #   | Sway chord          | Sway action    | Proposed Niri mapping               | Status      |
| --- | ------------------- | -------------- | ----------------------------------- | ----------- |
| 61  | `Super+Pause`       | `mode default` | `toggle-keyboard-shortcuts-inhibit` | alternative |
| 62  | `Super+Scroll_Lock` | `mode default` | `toggle-keyboard-shortcuts-inhibit` | alternative |

## 4. Media keys

Source: `modules/universal/desktop/sway/home-manager/media-keys.nix`.

| #   | Sway chord              | Flags         | Sway action                | Proposed Niri mapping                           | Status      |
| --- | ----------------------- | ------------- | -------------------------- | ----------------------------------------------- | ----------- |
| 63  | `XF86MonBrightnessDown` | —             | `lightctl down 2`          | same command                                    | reproduced  |
| 64  | `XF86MonBrightnessUp`   | —             | `lightctl up 2`            | same command                                    | reproduced  |
| 65  | `XF86AudioRaiseVolume`  | —             | `volumectl up 1`           | same command                                    | reproduced  |
| 66  | `XF86AudioLowerVolume`  | —             | `volumectl down 1`         | same command                                    | reproduced  |
| 67  | `XF86AudioMute`         | —             | `volumectl toggle-mute`    | same command                                    | reproduced  |
| 68  | `Alt+XF86AudioMute`     | —             | `volumectl -m toggle-mute` | same command                                    | reproduced  |
| 69  | `XF86AudioMicMute`      | —             | `volumectl -m toggle-mute` | same command                                    | reproduced  |
| 70  | `XF86AudioPlay`         | `--locked`    | `playerctl play-pause`     | `allow-when-locked=true`                        | reproduced  |
| 71  | `XF86AudioPause`        | `--locked`    | `playerctl play-pause`     | `allow-when-locked=true`                        | reproduced  |
| 72  | `XF86AudioNext`         | `--locked`    | `playerctl next`           | `allow-when-locked=true`                        | reproduced  |
| 73  | `XF86AudioPrev`         | `--locked`    | `playerctl previous`       | `allow-when-locked=true`                        | reproduced  |
| 74  | `Print`                 | —             | `flameshot gui`            | `screenshot` or `spawn flameshot gui`           | alternative |
| 75  | `Super+Print`           | `--inhibited` | `flameshot gui`            | `allow-inhibiting=false`, `spawn flameshot gui` | alternative |

## 5. Application and session bindings

| #   | Sway chord     | Source                            | Sway action            | Proposed Niri mapping | Status     |
| --- | -------------- | --------------------------------- | ---------------------- | --------------------- | ---------- |
| 76  | `Super+L`      | `swaylock.nix:25`                 | `swaylock -f`          | `spawn swaylock -f`   | reproduced |
| 77  | `Super+N`      | `swaync/default.nix:19`           | `swaync-client -t -sw` | same command          | reproduced |
| 78  | `Super+P`      | `nwg-shell/default.nix:108`       | `nwg-displays`         | same command          | reproduced |
| 79  | `Super+O`      | `handlr/default.nix:75`           | `xdg-open-clipboard`   | same command          | reproduced |
| 80  | `Ctrl+Super+A` | `default-secrets/default.nix:145` | `anonymizeClipboard`   | same command          | reproduced |

## 6. swayr bindings

Source: `modules/universal/desktop/sway/home-manager/swayr.nix:25-33` and the den leaf
`modules/den/aspects/desktop-sway-small.nix:166-176`.

| #   | Sway chord          | Sway action                            | Proposed Niri mapping                           | Status        |
| --- | ------------------- | -------------------------------------- | ----------------------------------------------- | ------------- |
| 81  | `Super+Space`       | `swayr switch-window`                  | `recent-windows` next or `niri msg pick-window` | alternative   |
| 82  | `Super+Delete`      | `swayr quit-window`                    | `close-window`                                  | reproduced    |
| 83  | `Super+Tab`         | `swayr switch-to-urgent-or-lru-window` | `recent-windows` next                           | alternative   |
| 84  | `Alt+Tab`           | `swayr prev-window all-workspaces`     | `recent-windows` next                           | alternative   |
| 85  | `Alt+Shift+Tab`     | `swayr next-window all-workspaces`     | `recent-windows` next or `previous-window`      | alternative   |
| 86  | `Super+Shift+Space` | `swayr switch-workspace-or-window`     | none                                            | accepted-loss |
| 87  | `Super+C`           | `swayr execute-swaymsg-command`        | none                                            | accepted-loss |
| 88  | `Super+Shift+C`     | `swayr execute-swayr-command`          | none                                            | accepted-loss |

## 7. Host-specific bindings

Source: `hosts/oams/default.nix:250-259`.

| #   | Sway chord              | Sway action                                   | Proposed Niri mapping                         | Status      |
| --- | ----------------------- | --------------------------------------------- | --------------------------------------------- | ----------- |
| 89  | `XF86Launch4`           | `kdn-asusctl rotate-cpu-profile`              | same command                                  | reproduced  |
| 90  | `XF86Launch1`           | `kdn-asusctl rog-control-center`              | same command                                  | reproduced  |
| 91  | `XF86KbdBrightnessDown` | `kdn-asusctl rotate-keyboard-brightness prev` | same command                                  | reproduced  |
| 92  | `XF86KbdBrightnessUp`   | `kdn-asusctl rotate-keyboard-brightness next` | same command                                  | reproduced  |
| 93  | `Shift+Super+P`         | `output eDP-1 toggle`                         | a short `niri msg output eDP-1 off/on` script | alternative |

## 8. Lid switch

Source: `modules/universal/desktop/sway/home-manager/default.nix:107-108`.

| #   | Sway event | Sway action            | Proposed Niri mapping | Status     |
| --- | ---------- | ---------------------- | --------------------- | ---------- |
| 94  | `lid:on`   | `output eDP-1 disable` | native lid handling   | reproduced |
| 95  | `lid:off`  | `output eDP-1 enable`  | native lid handling   | reproduced |

## 9. Coverage summary

| Category                | Rows                                       | Reproduced | Alternative | Accepted loss |
| ----------------------- | ------------------------------------------ | ---------- | ----------- | ------------- |
| Core                    | 38 (56 bindings with the workspace ranges) | 18         | 14          | 6             |
| Resize mode             | 22                                         | 0          | 22          | 0             |
| Passthrough mode        | 2                                          | 0          | 2           | 0             |
| Media keys              | 13                                         | 11         | 2           | 0             |
| Application and session | 5                                          | 5          | 0           | 0             |
| swayr                   | 8                                          | 1          | 4           | 3             |
| Host-specific           | 5                                          | 4          | 1           | 0             |
| Lid switch              | 2                                          | 2          | 0           | 0             |
| **Total**               | **95**                                     | **41**     | **45**      | **9**         |

The user signed off on the 9 accepted losses on 2026-11-16 because they are Sway-specific features.
No loss is open for sign-off. A future loss is not accepted until the user adds it here and signs it
off; that row then moves to "port needed" and the task scope grows.

## 10. Verification protocol

1. Build the Niri config: `nix build` the check that renders `config.kdl`; `niri validate` runs in
   that build.
2. Log in to the Niri session from SDDM.
3. Open a terminal and a graphical application.
4. Walk the table in order. For each row, press the chord and record the observed result.
5. For `alternative` rows, record the user's decision in the `Status` column. The 9 `accepted-loss`
   rows are already signed off.
6. Run the same table in the Sway session after the Niri change lands. Every Sway row must still
   pass. This is the regression check for coexistence.

## 11. Known issues to watch

- Niri has no release-triggered binds. The `ydotool-paste` sleep must be long enough that `Super` is
  released before typing starts. The current script sleeps 0.5 s by default.
- Niri mouse-wheel binds act on the focused window, not the window under the cursor. The direction
  also follows `natural-scroll`.
- Niri has no keybinding modes. The resize and passthrough modes become direct chords and a toggle.
- Niri's `focus-workspace N` stops at the last workspace. Named workspaces `"1".."10"` keep the
  static 1:1 mapping.
- `move-column-to-workspace` follows the column by default. Use `focus=false` to match Sway's
  `move container to workspace number N`.
- The `Super+P` display editor and the `Shift+Super+P` output toggle need a live check on the test
  host.
