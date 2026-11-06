# kdn-disko-zfs

Plan and apply the declarative ZFS datasets a host's **disko** config declares,
using [`numtide/disko-zfs`](https://github.com/numtide/disko-zfs) (this repo's
pinned flake input).

## Why

disko creates datasets **only at install time**. On an installed host, adding a
dataset to `hosts/<host>/disko.nix` writes it into `fileSystems` on the next
switch, but the dataset is never created — so the mount fails and activation can
hang. `disko-zfs` fills that gap: it compares a JSON *spec* of the desired
datasets against the live pool and emits `zfs create` / `zfs set` commands.

## Spec, per machine

The spec is generated from that host's NixOS config — every dataset under
`disko.devices.zpool.*.datasets`, with disko's `options` as ZFS properties. It is
always in step with `hosts/<host>/disko.nix`; nothing is hand-written.

```sh
kdn-disko-zfs spec -H oams        # print the spec JSON for a host
```

## Commands

| command            | does                                                              |
| ------------------ | ----------------------------------------------------------------- |
| `spec`             | print the generated spec JSON                                     |
| `show`             | dump the live pool's spec (what exists now)                       |
| `plan` *(default)* | `show` + `plan`; prints additive and destructive commands, changes nothing |
| `apply`            | apply the additive commands                                       |

Options: `-H/--host`, `-r/--repo`, `-s/--spec-file`, `--dry-run`, `--force`,
`--disko-zfs`.

```sh
kdn-disko-zfs plan  -H oams      # looks, changes nothing
kdn-disko-zfs apply -H oams      # creates the missing datasets
kdn-disko-zfs plan  -H oams --dry-run   # host down: print implied creates only
```

## Safety

`plan`/`apply` auto-add every **live** dataset the disko config does not declare
(container/podman storage, libvirt volumes, ...) to `ignoredDatasets`, so
`disko-zfs` never proposes destroying them. `apply` then refuses if any
`zfs destroy` remains, unless `--force`.

> The raw `disko-zfs plan` against an unfiltered spec will happily propose
> destroying your podman storage. That is exactly what this wrapper's automatic
> ignore step prevents.

## Architecture

The `disko-zfs` **binary** must match the target host's CPU architecture. The
wrapper resolves it at runtime: devenv's copy when the arch matches this machine,
otherwise a `nix build` of the target-system package from the repo's pinned input.
All logic that can be wrong is in `kdn_disko_zfs/core.py` and unit-tested in
`tests/` (`python3 -m unittest discover -s tests -t .`).

## Wiring it declaratively (the intended end state)

Import the upstream NixOS module so a switch applies the datasets automatically:

```nix
imports = [ inputs.disko-zfs.nixosModules.default ];
disko.zfs.enable = true;                    # derives datasets from disko.*
disko.zfs.settings.ignoredDatasets = [ "oams-main/containers/*" "oams-main/volumes/*" ];
```

With that in place, `nixos-rebuild --sudo dry-activate` prints what it would do,
and a real switch runs `disko-zfs apply` via its own unit — no manual wrapper
needed. This wrapper is the on-demand / cross-host equivalent for now.
