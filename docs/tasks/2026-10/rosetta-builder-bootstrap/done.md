---
type: Solution
description: Phases 2 and 3 ran on 2026-10-11 with the guest created directly on the external volume. Both Linux architectures build on `rosetta-builder`; the stock builder is detached.
timestamp: 2026-10-11T16:45:00+02:00
authored_by: agent
---

# Solution

## Result

`anji` is at phase 3 steady state: `legacyLinuxBuilder = false; rosettaBuilder = true;
bootstrapBuilder = false;`. `/etc/nix/machines` lists `rosetta-builder` with
`aarch64-linux,x86_64-linux` (plus the two `briv` entries). The stock builder VM is gone.

The guest was created directly on the external volume
(`kdn.darwin.rosetta-builder.guest.workingDir = "/anji-ext-01/rosetta-builder"`, the fork input
`nazarewk/nix-rosetta-builder`), so the follow-up
[rosetta-builder-external-drive](../rosetta-builder-external-drive/definition.md) folded into this
run instead of destroying a guest later.

## Evidence (2026-10-11)

- `nix build nixpkgs#legacyPackages.{aarch64,x86_64}-linux.hello` — both succeed.
- Non-cached probes (`runCommand` with a unique `builtins.currentTime`): `building
  '/nix/store/…-probe.drv' on 'ssh-ng://rosetta-builder'` for both architectures — real builds, not
  substitutes.
- `pgrep` shows the lima hostagent running with `--pidfile
  /anji-ext-01/rosetta-builder/.lima/rosetta-builder-vm/…` and `launchctl list` shows
  `org.nixos.rosetta-builderd` loaded — a launchd daemon serving from the external volume with no
  new Full Disk Access grant beyond what `linux-builder` already needed.
- Phase 2 (both builders on) built the custom 6-core stock image and the Rosetta image on the same
  day; phase 3 detached the stock builder without touching the Rosetta guest.

## Two blockers found during the run

1. **The `darwin-rebuild` wrapper honoured an ambient `name` env var.** A devenv shell exports
   `name=devenv-shell-env`, so `darwin-rebuild switch remote=anji` silently targeted
   `darwinConfigurations.devenv-shell-env` and built locally. Fixed in
   `packages/darwin-rebuild/darwin-rebuild.sh`: the script variable is now `kdn_host` and the env
   override is the dedicated `KDN_DARWIN_HOST`.
2. **A stale GitHub token on `anji`.** `anji` predated the token rotation in
   `default.unattended.sops.yaml`, so the remote flake input fetch got `401 Bad credentials`. The
   workaround: truncate `/etc/nix/nix.access-tokens.auto.conf` (mode 0444) on `anji`, kickstart
   `org.nixos.nix-daemon`, run the switch — the activation re-renders the fresh token from the
   repo's own secret. Confirmed `200` from `api.github.com` afterwards.

## Left open (not blocking)

- From `anji`, the `briv` builders fail to connect: `briv.lan.etra…` answers SSH but rejects the
  builder key (`Permission denied (publickey)`), and `briv.priv.nb…` does not resolve. `anji` no
  longer needs `briv` (Rosetta covers both architectures locally), so this is recorded, not chased.
- Reboot test: the launchd unlock-before-daemon ordering at boot is trusted from the
  `linux-builder` precedent but not re-measured for `rosetta-builderd`.
