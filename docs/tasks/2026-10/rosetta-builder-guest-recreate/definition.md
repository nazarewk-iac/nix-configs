---
type: Task
description: The nix-rosetta-builder daemon deletes and recreates the Lima guest whenever the generated lima.yaml differs from the stored one, and a nixpkgs bump changes that file every time.
status: open
authored_by: agent
timestamp: 2026-10-16T11:05:00+02:00
---

# rosetta-builder guest recreation drift

## 1. Problem

`anji` builds Linux derivations in one Lima guest. The guest disk carries a large Nix store:
the owner sized it for 200+ GB of build results (see `hosts/anji/default.nix:222-224`, disk
`1024GiB` set at `hosts/anji/default.nix:233`).

The daemon that owns the guest runs a consistency check at every daemon start. It compares the
`lima.yaml` the current nix configuration generates against the `lima.yaml` the instance stored.
On any difference it runs `limactl delete --force` and `limactl create`. The guest disk and its
whole Nix store go with it.

One line of the generated file makes every flake update a difference. The image reference is a
store path, and the qcow2 file name carries the nixpkgs version:

```yaml
images:
- location: >-
    /nix/store/kfxv598rx3rsvhadj2wacznnh53xx1z9-nixos-disk-image/
    nixos-image-efi-qcow2-26.11.20261011.7fd4004-aarch64-linux.qcow2
```

Any nixpkgs bump changes both the hash and the version in that string. The 2026-10-15 cutover hit
exactly this: the stored instance still named the 2026-09-08 image, the new configuration named
the 2026-10-11 image, and the check recreated the guest. See the mechanism, every trigger, and the
measured state in [research.md](research.md).

## 2. Why it matters

1. Every nixpkgs bump costs a full guest wipe on the first daemon start after the activation:
   VM re-download, cold guest store, re-fetch or re-build of every input.
2. The wipe is silent. The daemon logs to launchd. Nothing asks first.
3. An activation while the guest is up can interrupt in-flight builds before the recreate even
   starts: the wrapped daemon process dies with the job reload. (Inferred from the unit shape;
   not measured. See [research.md](research.md) section 5.)

## 3. Acceptance criteria

1. A nixpkgs bump that changes no `nix-rosetta-builder.*` option must not change the generated
   `lima.yaml`. The daemon's `cmp` must pass after such a bump, and the guest must survive.
2. A deliberate guest refresh (image update, resource change) must stay possible through one
   named, explicit action.
3. The daemon must never run `limactl delete --force` on a mismatch that only the volatile image
   path caused. An operator change to a real resource field may still recreate, but the recreate
   must say what it will destroy first.
4. Update the warnings that describe the current destroy-on-any-yaml-diff behaviour:
   `hosts/anji/default.nix:224-228`, `modules/slots/rosetta-builder/default.nix:25-29`,
   and the matching notes in `modules/den/aspects/rosetta-builder.nix`.
5. Keep `checks/den-mvp/tests.nix` (`den-eval-rosetta-builder`) passing.

## 4. Out of scope

- No live change on `anji` from this task. Research is recorded in [research.md](research.md);
  the fix needs its own change and a planned cutover.
- The fork change itself (candidate fixes are in [research.md](research.md) section 7).
