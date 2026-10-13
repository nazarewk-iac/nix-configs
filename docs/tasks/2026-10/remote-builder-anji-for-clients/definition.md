---
type: Task
description: Let a host dispatch an aarch64-linux build to `anji` directly, so `anji` serves that system to every host and forwards the build to its own Rosetta builder.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-10-14T00:03:02+02:00
---

# Serve `aarch64-linux` from `anji` to every host

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

`anji` is an `aarch64-darwin` Mac. It runs a QEMU `aarch64-linux` builder VM (the
[Rosetta builder](../2026-10/rosetta-builder-bootstrap/definition.md)). Its own
`nix.buildMachines` lists that VM as `ssh-ng://rosetta-builder`.

A second host, `oams` (`x86_64-linux`), cannot build `aarch64-linux` natively. It needs `anji`
as a builder. The earlier design registered a separate `anji-linux-builder` host name that reaches
the VM through an SSH `ProxyJump`, but that name does not resolve from a client outside `anji`.

## Problem

The client should reach `anji` itself, and `anji` should forward the foreign build to its own
builder VM. Three things were wrong:

1. The `anji` build-machine entry advertised only the darwin systems, so a client never sent an
   `aarch64-linux` build to it.
2. The builder SSH identity sat in a Home Manager block, which the nix daemon (it runs the build
   hook as root) does not read.
3. With the account trusted on `anji`, `anji` did not forward the build at all. The cause is a Lix
   behaviour, recorded in [docs/lix-caveats.md](../../../lix-caveats.md).

## Approach

- Register `anji` with `aarch64-linux` in its `systems`, and drop the `anji-linux-builder` entry
  and its `ProxyJump` SSH block.
- Move the builder identity to the system SSH config.
- Put the remote-build account in `allowed-users` and keep it out of `trusted-users`, so the build
  hook keeps its forward path.
