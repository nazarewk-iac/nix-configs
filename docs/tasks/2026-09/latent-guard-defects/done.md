---
type: Solution
task: definition.md
description: Both guard defects take a context-correct test, and one check per defect forces the path that laziness hid.
authored_by: agent
timestamp: 2026-09-11T00:00:00Z
---

# Two latent guard defects — solution

Parent: [definition.md](definition.md).

## Root cause analysis

Both defects share one root cause: **a guard or an option read that assumes a context the
module does not run in.**

`hasParentOfAnyType` walks the parent chain. A probe measured the chain: a NixOS host holds one
parent, the root meta config, with `moduleType = "root"`. So `hasParentOfAnyType [ "nixos" ]` is
`false` on the host and `true` in Home Manager below it. The keepassxc module used that test to
name a Linux-only package, so the package reached the user profile alone. 25 of the 30 call
sites want a platform test instead.

`config.boot.kernelPackages` names a NixOS option. The containers module read it inside an
`ifHM` branch, where the option does not exist. Nix laziness hid the read: a force of
`containersConf.settings` reaches `builtins.attrNames` alone, and that forces no value.

A force of the list element ends the evaluation. The message is `error: attribute 'boot'
missing`, a selection error, so `builtins.tryEval` does not catch it. Measured 2026-09-11.

## Solution

| Defect | Fix |
|---|---|
| keepassxc guard | `lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.kdn.kdn-keepass` |
| containers read | `osConfig ? null` argument, plus `hasOciHook = osConfig != null && osConfig ? boot && osConfig.boot ? kernelPackages` |

The null test comes first, so neither `?` probe ever reads a null value. `null ? boot` returns
`false` in this Nix, but the order states the intent and does not depend on that. The two `?`
probes cover the remaining shapes: an empty attrset, and a Darwin parent with no `boot` option.

`checks/universal-guards.nix` holds one assertion set per defect:

- `universal-eval-keepassxc` — it forces `kdn.env.packages` of the module in the NixOS context
  and in the Home Manager context, over a Linux pkgs set and a Darwin pkgs set.
- `universal-eval-containers` — it forces every leaf of `containersConf.settings` in the Home
  Manager context, with a parent, with a null parent and with an empty parent.

Both checks join `bundle-core` through the `universal-eval-` name prefix.

## Verification steps

```bash
SYS=aarch64-darwin   # or x86_64-linux, or aarch64-linux
nix build --no-eval-cache -L ".#checks.$SYS.universal-eval-keepassxc"
nix build --no-eval-cache -L ".#checks.$SYS.universal-eval-containers"
nix build --no-eval-cache -L --keep-going ".#checks.$SYS.bundle-core"
```

Each check prints `universal-eval <name>: 3 of 3 assertions pass`.

## Follow-up notes

29 other `hasParentOfAnyType` call sites remain, one per file. The task states that 25 of the 30
want `pkgs.stdenv.hostPlatform.isLinux`. This task fixed the one site the exit test names. A
follow-up task must read each remaining site and choose per intent:

`modules/universal/_stylix.nix`, `desktop/base/`, `desktop/sway/home-manager/` (and its
`kanshi/`, `nwg-shell/`, `nwg-shell/nwg-panel/`, `swaync/` children), `emulation/wine/`,
`profile/user/bn/`, `profile/user/kdn/`, `profile/user/sn/`, `programs/beeper/`,
`programs/blender/`, `programs/element/`, `programs/ente-photos/`, `programs/kdeconnect/`,
`programs/nextcloud-client/`, `programs/orca-slicer/`, `programs/rambox/`, `programs/signal/`,
`programs/slack/`, `programs/spotify/`, `programs/ssh-client/`, `programs/tidal/`,
`programs/weechat/`, `programs/wofi/`, `services/syncthing/`, `toolset/print-3d/`,
`virtualisation/containers/`.

`virtualisation/containers/default.nix` keeps its parent test on purpose: the branch really
needs a NixOS parent, because it reads one.
