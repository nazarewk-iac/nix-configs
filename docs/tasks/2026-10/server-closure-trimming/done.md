---
type: Solution
description: Add kdn.minimalServer, gate each heavy closure item on it or on kdn.desktop.enable, repair kdn-nix-collect-garbage, and record the booted-system GC rule.
task: definition.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Solution

## Root cause analysis

Two independent causes held the store above the closure.

1. **Stale GC roots.** `kdn-nix-collect-garbage` derived its user list from `getent passwd`, so a
   deleted user (uid 1000, no passwd entry) kept a live home-manager profile. It also treated a
   `home-manager-N-link` as active whenever the sibling `home-manager` link pointed at it, so a
   stale generation survived. The `nix-store --gc --print-roots` output confirmed the stale roots.
2. **A bloated closure.** `hardware_report` pulled the full Rust toolchain, `nextcloud-client`
   pulled `qtwebengine` and Qt 6, stylix forced `qt.enable` on a headless host, and `toolset.tracing`
   pulled `clang` and `llvm`. `documentation.nixos`, `nix-derivation` (GHC), `nmap`,
   `wireshark-cli`, Helix, `hardinfo2`, `difftastic`, `geoclue2` and the Qt `pinentry-all` added more.

## Solution

`packages/kdn-nix/kdn-nix-collect-garbage.sh`:

- `clean_orphaned_users` removes `/nix/var/nix/{profiles,gcroots}/per-user/<name>` when the name has
  no passwd entry.
- `handle_leftover_profile` keeps a `home-manager-N-link` only when the home `current-home` gcroots
  points at it.
- The default action list names the action `orphaned_users`, matching the function name.

`modules/universal/_options.nix`: add `kdn.minimalServer` (bool, default `false`).

Gated on `kdn.minimalServer`:

- `documentation.nixos.enable`, `documentation.man.*` (`modules/universal/default.nix`).
- `nix-derivation` (GHC), `nmap`, `wireshark-cli`, Helix (`toolset/nix`, `toolset/network`,
  `headless/base`).
- `toolset.tracing` (`toolset/unix` and `toolset/fs`), `hw-probe` (`hw/basic`).
- `location.provider` keeps its upstream `manual` value (`profile/machine/baseline`).

Gated on `kdn.desktop.enable`:

- `nextcloud-client` default, the stylix `qt` target, `mesa-demos`, the Vulkan tools, `hardinfo2`.

Removed outright: the `hardware_report` flake input (it dragged the Rust toolchain).

Pinentry: `programs.gnupg` uses `pinentry-curses` for both the primary and the fallback on a
minimal server.

`hosts/moss`, `hosts/etra`, `hosts/briv` set `kdn.minimalServer = true`.

`docs/nix-dev.md` records that a collection after a switch cannot free the closure of the
generation that the machine booted, and that the space returns after a reboot or a `kexec`.

## Verification steps

- `moss`: store 22 GB -> 7.7 GB, disk free 9.7 GB -> 23 GB, closure 10.4 GiB -> 4.19 GiB, one
  generation left, zero dead paths.
- `etra`: closure 8.00 GiB -> 4.26 GiB. `briv`: 9.09 GiB -> 7.42 GiB.
- `brys` and `oams` (desktop) keep every gated package; their closures are unchanged.

## Follow-up notes

- `briv` stays larger than `moss`/`etra`. It keeps the RPi kernel and firmware (~1.35 GiB), Home
  Assistant (~1.40 GiB), and the `baseline` primary-user home-manager profile (~2.1 GiB, including
  a 1.5 GiB store copy of the repository source).
- The closure item list is a snapshot. Re-measure with `nix path-info -r --json /run/current-system`
  after a flake update.
