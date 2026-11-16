---
type: Design
description: The typed kdn.desktop-niri option tree, its KDL rendering rules, the shortcut-parity gate, and the UWSM A/B scorecard.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T17:12:00+01:00
---

# Niri composable configuration design

## 1. Design goals

1. One typed Nix surface generates the Niri KDL. The user states intent, not KDL syntax.
2. The surface composes across aspects. A leaf aspect adds binds, rules, or startup commands without
   rewriting the core.
3. The build validates the result with `niri validate`.
4. The Sway shortcut inventory is the input to the Niri bind generation, and a check proves coverage.
5. The first spike stays small. It proves the model before it grows.

## 2. Layers

```
modules/den/common/desktop-niri.nix
  kdn.desktop-niri.keys          the 13 friendly names, shared with Sway
  kdn.desktop-niri.bindings      the normalized catalog (list of attrsets)

modules/den/aspects/desktop-niri.nix
  declaration                    every option below
  nixosTarget                    programs.niri, xwayland-satellite, portals, agents
  homeTarget                     wayland.windowManager.niri.settings + extraConfig
  leaves                         waybar, kanshi, swaylock, swaync, media keys
```

This mirrors `modules/den/aspects/desktop-sway.nix` and the shared
`modules/den/common/desktop-sway.nix`.

## 3. Option tree

| Option           | Type                                | Renders to                                                             |
| ---------------- | ----------------------------------- | ---------------------------------------------------------------------- |
| `package`        | `nullOr package`                    | `wayland.windowManager.niri.package`; `null` keeps the nixpkgs default |
| `keys`           | `attrsOf str`                       | no direct output; the bind catalog uses it                             |
| `bindings`       | `listOf binding`                    | `settings.binds`                                                       |
| `spawnAtStartup` | `listOf (listOf str)`               | ordered `spawn-at-startup` children                                    |
| `windowRules`    | `listOf (listOf node)`              | ordered `window-rule` children                                         |
| `outputs`        | `listOf output`                     | ordered `output` children                                              |
| `workspaces`     | `listOf workspace`                  | ordered `workspace` children                                           |
| `layout`         | freeform attrset                    | `settings.layout`                                                      |
| `input`          | freeform attrset                    | `settings.input`                                                       |
| `animations`     | freeform attrset                    | `settings.animations`                                                  |
| `environment`    | `attrsOf str`                       | `settings.environment`, which reaches niri's children only             |
| `session`        | enum `niri-session`, `niri`, `uwsm` | the desktop entry and the session units                                |
| `useNautilus`    | bool                                | `programs.niri.useNautilus`                                            |
| `portal.secret`  | enum `repo`, `gnome-keyring`        | `xdg.portal.config.niri` and the keyring toggle                        |
| `extraKdl`       | lines                               | `wayland.windowManager.niri.extraConfig`                               |

The `binding` submodule:

```nix
{
  chord = lib.mkOption { type = lib.types.str; };
  action = lib.mkOption { type = lib.types.str; };
  args = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
  allowWhenLocked = lib.mkOption { type = lib.types.bool; default = false; };
  allowInhibiting = lib.mkOption { type = lib.types.bool; default = true; };
  repeat = lib.mkOption { type = lib.types.bool; default = true; };
  source = lib.mkOption { type = lib.types.str; default = ""; };
  parity = lib.mkOption {
    type = lib.types.enum [ "reproduced" "alternative" "accepted-loss" ];
    default = "reproduced";
  };
  note = lib.mkOption { type = lib.types.str; default = ""; };
}
```

`action` stays a string because a wrong action name is caught by `niri validate`. A later version can
generate an enum from the pinned niri source, as `niri-flake` does, but that is not needed for the
first spike.

## 4. Rendering rules

### 4.1 Binds

```nix
settings.binds = lib.listToAttrs (map (b: {
  name = b.chord;
  value =
    { "${b.action}" = if b.args == [ ] then { } else b.args; }
    // lib.optionalAttrs (b.allowWhenLocked) {
      _props.allow-when-locked = true;
    }
    // lib.optionalAttrs (!b.allowInhibiting) {
      _props.allow-inhibiting = false;
    }
    // lib.optionalAttrs (!b.repeat) {
      _props.repeat = false;
    };
}) cfg.bindings);
```

Rules:

- Assert that every `chord` is unique. A duplicate chord is a configuration conflict, not a merge.
- Assert that every `source` points at a real Sway binding during the evaluation. A stale catalog
  entry is a bug.
- Keep one definition site per bind list. Do not let two aspects append to one `spawn` list.

### 4.2 Repeated top-level nodes

```nix
settings = {
  # ordinary sections
  input = cfg.input;
  layout = cfg.layout;
  animations = cfg.animations;
  environment = cfg.environment;

  # repeated, ordered nodes
  _children =
    map (entry: { spawn-at-startup._args = entry; }) cfg.spawnAtStartup
    ++ map (name: { workspace._args = [ name ]; }) cfg.workspaces
    ++ map (out: { output._args = [ out.name ]; } // out.settings) cfg.outputs
    ++ map (rule: { window-rule._children = rule; }) cfg.windowRules;
};
```

Rules:

- Never put a list of attribute sets in a plain attribute. It becomes `-` children.
- Never put window rules in an attribute set. Order is semantic.
- Keep `outputs`, `workspaces`, and `windowRules` as lists, not attribute sets.
- Put a comment in the module that states these rules, so a later edit does not undo them.

### 4.3 Escape hatch

`extraKdl` is appended after the generated file. Use it for a section the typed surface does not
model yet. Every use must carry a comment that names the missing option.

### 4.4 Validation

```nix
wayland.windowManager.niri = {
  enable = true;
  checkConfig = true;
  settings = renderSettings cfg;
  extraConfig = cfg.extraKdl;
};
```

`checkConfig` runs `niri validate --config`. This catches a wrong action name, a wrong property, and
the `-` children mistake.

## 5. Shortcut parity gate

The gate has three parts.

### 5.1 Source of truth

The normalized catalog is the source of truth for Niri. The Sway tree remains the source of truth
until the catalog is complete. Phase 0 copies every Sway binding into the catalog with its exact
`source`.

### 5.2 Evaluation-time coverage assertion

In the Home Manager target:

```nix
assert lib.all (b: b.source != "") cfg.bindings;
assert builtins.length (lib.unique (map (b: b.chord) cfg.bindings))
       == builtins.length cfg.bindings;
```

In the den check:

```nix
expected = builtins.attrNames swayConfig.keybindings;
actual = map (b: b.swayChord) catalog;
```

The check must treat mode keys separately, because `modes.resize` and `modes.passthrough` are not in
`config.keybindings`. The catalog therefore carries an explicit `mode` field, and the check compares
three sets: default bindings, resize-mode bindings, and passthrough-mode bindings.

### 5.3 Live checklist

`shortcuts.research.md` has one row per binding. The user runs the checklist in a Niri session and marks each
row. A row is complete only when it is `reproduced` or the user signed off on the `alternative` or
`accepted-loss` entry. The 9 `accepted-loss` rows are already signed off (2026-11-16); only the
`alternative` rows need a live decision.

## 6. UWSM A/B scorecard

Score each criterion from 0 to 2. A total of 14 or more out of 20 is a pass. Record the scores in
`done.md`.

| Criterion                                                                                            | 0                   | 1                   | 2               |
| ---------------------------------------------------------------------------------------------------- | ------------------- | ------------------- | --------------- |
| Login reaches `graphical-session.target`                                                             | no                  | partial             | yes             |
| Environment in the user manager (`WAYLAND_DISPLAY`, `DISPLAY`, `NIRI_SOCKET`, `XDG_CURRENT_DESKTOP`) | missing             | partial             | complete        |
| Portal and screencast                                                                                | broken              | partial             | work            |
| Teardown ordering                                                                                    | stale units         | some stale          | clean           |
| Crash then relogin                                                                                   | reboot needed       | reset-failed needed | no manual step  |
| XDG autostart                                                                                        | never               | duplicate           | once            |
| App slices                                                                                           | none                | partial             | correct         |
| `XDG_CURRENT_DESKTOP` selection                                                                      | wrong portal config | unknown             | correct         |
| Custom unit count                                                                                    | many                | some                | zero            |
| Upstream support                                                                                     | unsupported         | workaround          | documented path |

The comparison is plain `niri-session` versus `niri-uwsm`. The plain session is the control.

## 7. First spike scope

Keep the first spike small:

- one host;
- one Niri config file;
- core binds only: terminal, launcher, close, focus, move, workspaces 1–4, fullscreen, floating,
  lock, screenshots, media keys;
- waybar with `niri/workspaces` and `niri/window`;
- swaync, swaylock, and swayidle;
- kanshi with one profile;
- native lid handling;
- XWayland with one JetBrains IDE and one X11 application.

Do not include VNC, headless output, the full window-rule set, stylix colours, or per-window cgroup
assignment in the first spike.

## 8. Alternatives considered

| Alternative                                 | Why not                                                                                                                                    |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Hand-written `config.kdl`                   | Not composable and not typed. The task exists to avoid this.                                                                               |
| `niri-flake` `programs.niri.settings`       | A fourth flake input, a second nixpkgs pin, a module that disables the nixpkgs module, and a schema behind 26.04.                          |
| `extraConfig` only                          | Simple, but it gives no option tree and no cross-aspect composition.                                                                       |
| A generated file per concern with `include` | `include` is positional, and multipart sections do not merge. Start with one file. Split only if the file becomes unreviewable.            |
| A NixOS-side `/etc/niri/config.kdl`         | Home Manager writes `~/.config/niri/config.kdl`, and niri never reads `/etc` when the user file exists. The NixOS side is a fallback only. |

## 9. Decision record

| Decision                   | Choice                                             | Reason                                                          |
| -------------------------- | -------------------------------------------------- | --------------------------------------------------------------- |
| Dependency on `niri-flake` | no                                                 | Borrow the shape, not the input.                                |
| Primary config carrier     | Home Manager `wayland.windowManager.niri.settings` | Typed Nix, build-time validation, one file.                     |
| Raw KDL                    | `extraKdl` only                                    | Escape hatch for unmodelled sections.                           |
| Shortcut source            | shared binding catalog                             | One source of truth and an automatable coverage gate.           |
| First session              | plain `niri-session`                               | It is the control for the UWSM A/B, and it is upstream's path.  |
| Portal default             | keep `gnome` and `gtk`                             | It is what niri needs for screencast; revisit the Secret owner. |
