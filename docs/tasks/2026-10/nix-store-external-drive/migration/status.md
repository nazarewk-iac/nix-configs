---
type: Status
description: The store is cut over to the external volume on `anji` (2026-10-15); soak, the drive-absent acceptance test, and internal-volume removal remain.
task: definition.md
authored_by: agent
timestamp: 2026-10-15T17:50:00+02:00
---

# Status checkpoint — 2026-10-15

## Done so far

- Stage 0: volume `Nix Store Ext` (disk7s2, unencrypted on the encrypted `anji-ext-02`
  container), the full mirror of `/nix` including `var/` and `nix-installer`, and
  `packages/kdn-nix-bootstrap`.
- Stage 1: `storeOnExternal = true` activated on `anji` (Oct 15 ~05:00): every nix daemon runs as
  a bootstrap child, builds green, all 8 job payload files match the live plists.
- Stage 2: Full Disk Access granted to `/usr/local/bin/kdn-nix-bootstrap` by the owner; the
  macOS-27 tree-model probe **passed** — a nix bash, a grandchild of the granted binary, wrote to
  a USB volume from a real launchd job (`tcc-ok`, 09:04).
- Stage 3: cutover executed (Oct 15 09:12–10:19): daemon bootout, final `rsync --delete` pass
  (rc 0, dry-run clean apart from the two runtime socket files), `/etc/fstab` `/nix` line flipped
  to `A8D810B7-…` (backup `/etc/fstab.pre-cutover-2026-10-15`), installer hook plist removed,
  reboot, owner console unlock.
- Verified after boot: `mount` shows `/dev/disk7s2 on /nix`; `bootstrap status` = mounted;
  `nix-daemon` is a child of the wrapper; a cache-less **x86_64-linux source build ran on the
  rosetta guest** through the wrapped, socket-activated `rosetta-builderd` — the launchd socket
  handoff resolves per job, for every process of it, so no descriptor re-pass is needed (measured
  fact that killed the earlier `passFds` idea). sops-install-secrets ran clean; `darwin-store`
  exit 0. `/nix` holds 102 G of 1.9 T.
- Moss zellij-web check (the owner's chosen test host): HTTP 200 over TLS, leaf
  `CN=moss.priv.nb.net.int.kdn.im` valid to 2027-01-10, key served from
  `/run/secrets/kdn/certificates/zellij-web.key` (sops-nix).

## Remaining

- **Owner action: re-grant Full Disk Access to `/usr/local/bin/kdn-nix-bootstrap`.** The stage-3
  verification run included an activation that re-installed the binary in place; macOS flipped
  the TCC entry to DENIED (auth_value 0) and the wrapped daemons lost volume access. The original
  granted bytes are back at the path (install-once semantics now enforced in the config); the GUI
  entry must be toggled/re-added once. Then: kickstart every wrapped daemon, re-run the probe set,
  and re-run the source-build + guest-build acceptance.
- Soak at least one week with the internal `Nix Store` volume untouched as the rollback (it is
  pinned `noauto,nobrowse` in fstab and unmounted).
- `limactl`/builder guest image drift (instance yaml 0908 image vs 1011 config) recreates the
  guest whenever the check runs — unrelated to the store, but it delays the first build after a
  boot. Track it with the rosetta-builder tasks.
- Delete the internal `Nix Store` volume after the soak.

## Next directions

- Run acceptance test 4: drive-absent boot (macOS boots to a login prompt; the bootstrap waits;
  re-plug recovers without activation).
- Remove the per-path bash Full Disk Access grants once the soak passes; re-run the probe set of
  `docs/darwin-quirks.md` after the next nixpkgs bump to prove grant-stability.
