---
type: Status
description: Both guest-sshd fixes are in hosts/anji/default.nix but unactivated; the switch is blocked because the briv.lan builder ran out of disk while rebuilding the guest image.
task: definition.md
authored_by: agent
timestamp: 2026-10-18T06:00:00+02:00
---

# Parked: guest sshd fixes written, activation blocked on briv disk

## Done so far

- **Live investigation on `anji` (macOS 27.0.1)** found two independent defects that stop the Lima
  guest sshd from coming up. Root cause and evidence are in
  [research.md](research.md#2026-10-18-live-investigation).
- **Both fixes are written in `hosts/anji/default.nix`** (unactivated):
  1. `launchd.daemons.rosetta-builderd.path = lib.mkBefore [ "/usr/bin" ]` — puts `/usr/bin`
     first so the lima guest bootstrap runs the system openssh (with GSSAPI) instead of the
     nixpkgs openssh. Verified: the eval'd PATH starts with `/usr/bin` and matches a live plist
     edit byte-for-byte.
  2. `nix-rosetta-builder.onDemand = false` plus
     `launchd.daemons.rosetta-builderd.serviceConfig.Sockets = lib.mkForce { }` — drops socket
     activation, sets `KeepAlive = true`, and clears the empty `Sockets` key the fork leaves
     behind.
- The live plist on `anji` is hand-patched to the intended state, but the daemon is **not loaded**.
  The system stays on the previous generation.

## Blocker

- A `nix run '.#darwin-rebuild' -- switch remote=anji` was attempted. It **failed after 1h48m**
  because the remote builder `briv.lan` ran out of disk space while building the aarch64-linux
  NixOS guest image: `cat: write error: No space left on device` for
  `/nix/store/...-nixos-disk-image.drv`.
- `onDemand = false` changes the guest image (`logind` `IdleAction` is baked into it), so the
  image genuinely rebuilds. The switch cannot finish until `briv` has free disk.

## Next directions

1. Free disk space on `briv.lan`.
2. Re-run `nix run '.#darwin-rebuild' -- switch remote=anji`.
3. Verify the guest boots and an x86_64-linux build runs through the daemon.

Note for the fork: this fixes the daemon lifecycle only. A fork fix should drop the `Sockets` key
entirely instead of emptying it.
