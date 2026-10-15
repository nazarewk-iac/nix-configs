---
type: Status
description: Stages 0 and 1 are done and stage 1 is activated on `anji`; the stage 2 probe and the stage 3 cutover run right now; soak and internal-volume removal remain.
task: definition.md
authored_by: agent
timestamp: 2026-10-15T14:32:44+02:00
---

# Status checkpoint — 2026-10-15

## Done so far

- Stage 0: volume `Nix Store Ext` (disk7s2, unencrypted on the encrypted `anji-ext-02`
  container), the full 89 G mirror of `/nix` (pass 2 carried `var/` and `nix-installer`, not just
  `store`), and `packages/kdn-nix-bootstrap`.
- Stage 1: `storeOnExternal = true` activated on `anji` on Oct 15 around 05:00. Verified:
  `nix-daemon` runs as a bootstrap child, builds are green, and all 8 job payload files match the
  live plists.
- Two code fixes landed with stage 1: the `passFds` socket re-pass (launchd fd 3 for
  `rosetta-builderd` survived the Go spawn), and real config files instead of `environment.etc`
  symlinks (the symlinks resolve through `/nix/store` before it is mounted).
- Moss zellij-web check (the owner's chosen test host, 2026-10-15): HTTP 200 over TLS from `oams`;
  the leaf serves `CN=moss.priv.nb.net.int.kdn.im`, issued by `CN=KDN certificates root CA`,
  valid to 2027-01-10. The sops-nix key path is live on moss: `ExecStart` reads
  `/run/secrets/kdn/certificates/zellij-web.key`.

## Remaining

- Stage 2 (Full Disk Access grant on `/usr/local/bin/kdn-nix-bootstrap`, then the macOS-27
  tree-model probe) and stage 3 (cutover window: final `rsync --delete`, fstab flip, reboot) are
  **in flight right now by another agent**. Record the outcome in `.worklog.md` when they land.
- Soak at least one week with the internal `Nix Store` volume untouched as the rollback.
- Delete the internal `Nix Store` volume after the soak.

## Next directions

- Run acceptance test 4: drive-absent boot (macOS boots to a login prompt; the bootstrap waits;
  re-plug recovers without activation).
- Remove the per-path bash Full Disk Access grants once the soak passes.
- Record the probe results in [docs/darwin-quirks.md](../../../../darwin-quirks.md).
