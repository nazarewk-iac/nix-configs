---
type: How-To
description: The rosec Secret Service provider on this tree — the fork, the module options, how to update it, the conflict workflow, and the KeePassXC migration.
timestamp: 2026-11-14T21:30:00+01:00
---

# rosec Secret Service

`rosec` is the Secret Service daemon (`org.freedesktop.secrets`) this tree uses. It runs as a
user service and stores secrets in the **`rosec-sops` provider**: a sops-encrypted file tree
under `~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage/`. The unlock factor is the
YubiKey age identity in `~/.config/sops/age/keys.txt` (the unattended PIV slot 3: PIN never,
touch never).

The daemon comes from the **`nazarewk-iac/rosec` fork** (`github:nazarewk-iac/rosec`), which adds
the native provider. The fork's own maintenance guide is `docs/MAINTAINING.md` in that
repository.

## What runs where

| Piece            | Location                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------- |
| Package          | `inputs.rosec.packages.<system>.rosec` (the fork's flake output)                            |
| Module (classic) | `modules/universal/services/rosec/default.nix`                                              |
| Module (den)     | `modules/den/aspects/service-rosec.nix`                                                     |
| Host config      | `hosts/oams/default.nix` (`kdn.services.rosec`)                                             |
| Provider config  | rendered to `~/.config/rosec/config.toml`                                                   |
| Store            | `~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage/`                             |
| Conflict report  | `rosec-conflicts` script, path unit + timer, state in `~/.local/state/rosec/conflicts.json` |

## Options

The universal module declares `kdn.services.rosec`:

- `enable` — run `rosecd`. **Off on `oams` until the migration**, because KeePassXC holds the bus
  name (two units cannot own `org.freedesktop.secrets`; the second one is killed).
- `package` — defaults to the fork's flake output.
- `extraPackages` — extra binaries on the unit `PATH`.
- `providers.sops.{path,key_file,age_recipient,sops_binary,sopsPackage,agePluginYubikeyPackage,probe_timeout_seconds}`.
- `ssh_fuse` — the built-in SSH agent/FUSE tree. Off here; the stock OpenSSH agent serves keys.
- `conflictNotification.{enable,notify,swaync,interval,stateFile}` — independent of `enable`; it
  reads the store, not the daemon.

The den aspect uses `use` instead of `enable` (the aspect rules forbid a reachable `enable`) and
targets `homeManager` only.

## Update rosec (including the fork)

1. **Update the fork** first. Follow `docs/MAINTAINING.md` in `nazarewk-iac/rosec`: fetch
   upstream, rebase `sops-provider` and `devenv`, re-join `main`, run the tests, push the
   bookmarks. The final `main` commit id is the new rev.
2. **Bump the input** in this repository:

   ```sh
   nix flake lock --update-input rosec
   git diff flake.lock   # confirm the new rev
   ```

3. **Build and switch** (commit the lock first; the tree is shared with other sessions):

   ```sh
   ./nixos-rebuild.sh switch
   ```

4. **Verify**:

   ```sh
   rosec --version
   rosec-sops conflicts list
   systemctl --user status rosec-keys.service
   systemctl --user status rosec-keys.path
   systemctl --user status rosec-conflicts.path rosec-conflicts.timer
   ```

   While `enable = false` (before the migration), test the provider against a **private bus**:

   ```sh
   rosecd --socket /tmp/rosec-test/bus --no-migrate &
   DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/rosec-test/bus \
     secret-tool store --label=poc service poc k v   # then lookup
   ```

   After the migration (`enable = true`), the live session bus serves the same clients.

## Conflict workflow

The provider resolves a conflict by **latest `modified` wins** and never deletes the loser:

- the losing copy is archived as `<id>.superseded-<nanos>-<host>.sops.yaml`;
- a plaintext, secret-free marker is written under `.conflicts/<collection>/<id>.md`;
- the item carries `rosec:sops-unresolved-conflict` until the marker is resolved.

The `rosec-conflicts` script notifies once per new conflict (swaync + desktop notification) and
records it in `~/.local/state/rosec/conflicts.json`. Resolve with the provider CLI:

```sh
rosec-sops conflicts list
rosec-sops conflicts show <item>
rosec-sops conflicts resolve <item> --keep winner|loser|file
```

The better long-term scheme is the follow-up task:
`docs/tasks/2026-11/rosec-conflict-resolution/definition.md`.

### Conflict runbooks

**A bad archive.** A `.superseded-*` file can be corrupt, or encrypted to a key you no longer have.
`rosec-sops conflicts show <item>` names the winner and the losers. If the canonical winner opens,
`resolve --keep winner` deletes the bad archive. If the canonical is the bad copy and the archive is
the good one, `resolve --keep loser` promotes it. If both are bad, restore the item from the
Nextcloud version history or the backup, then delete the marker. The marker is plaintext, so it
survives a store you cannot decrypt.

**Unbounded `.superseded-*` growth.** Every conflict archives a loser and never deletes it, so an
unresolved conflict costs disk and sync traffic forever. The timer reports every archive; resolve
with `conflicts resolve`, which deletes the loser. An orphan archive without a marker (a crash
between the archive write and the marker write) is listed by `rosec-conflicts --list`; inspect the
canonical, then delete the orphan by hand. A retention policy is a possible follow-up.

## Migrate from KeePassXC

KeePassXC still serves `org.freedesktop.secrets` on this host. The migration task
(`docs/tasks/2026-11/keepassxc-to-rosec-migration/definition.md`) reads the KDBX, writes the
items through the provider, verifies them, and then flips the one line:

```nix
kdn.services.rosec.enable = true;
```

Only after that flip may the KeePassXC unit be retired; until then both units target the same bus
name and systemd kills the loser.

## Troubleshooting

- **`org.freedesktop.secrets` is owned by KeePassXC** — expected while `enable = false`; use the
  private-bus test above.
- **`unlock` fails with `AuthFailed`** — the age identity does not match the store: check
  `key_file`, the YubiKey slot, and `sops -d` on one file by hand.
- **A conflict notification repeats** — the state file keys on the conflict path; delete the
  stale record in `~/.local/state/rosec/conflicts.json` if a file was removed by hand.
- **The daemon drops the provider after a config reload** — the fork must register the kind in
  the hot-reload match too; see `docs/MAINTAINING.md` in the fork.
