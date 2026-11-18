---
type: Task
description: A small Syncthing folder for the secrets that must exist before Nextcloud — pass, the rosec store, the KeePass database — with Etra as an always-on node and a versioned backup in Nextcloud.
status: open
authored_by: agent
timestamp: 2026-11-18T15:50:09+01:00
---

# A pre-Nextcloud secrets folder synced by Syncthing

## Context

Three things that a host needs **before** any login currently live inside the Nextcloud tree:

| Item            | Live path                                                          |
| --------------- | ------------------------------------------------------------------ |
| `pass` store    | `~/Nextcloud/drag0nius@nc.nazarewk.pw/important/password-store`     |
| rosec store     | `~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage`      |
| KeePass DB      | `~/Nextcloud/drag0nius@nc.nazarewk.pw/important/keepass/drag0nius.kdbx` |

That tree is not available when the Nextcloud client is logged out, on a fresh host, or while the
server is unreachable. Worse, the dependency is circular:

- Nextcloud stores its login credentials in the Secret Service (`rosec`);
- `rosec` reads its sops store from the Nextcloud tree;
- so Nextcloud cannot log in until rosec can read a folder that Nextcloud has not synced yet.

Measured on brys, 2026-11-18: the client showed the OAuth flow (`0\authType=webflow`,
`0\user=@Invalid()`) and the rosec store directory did not exist, because the ZFS copy of
`~/Nextcloud` predates the store created on oams on 2026-11-14. The store had to be copied by hand
and the provider config was missing entirely.

A small folder that Syncthing keeps on every host breaks the cycle: it is present at boot,
independent of the Nextcloud client, and Nextcloud keeps a **backup copy** instead of the live data.

## Goal

One Syncthing folder (working name `secrets`) that:

1. contains the small files a host needs before login;
2. is available on oams, brys and etra, plus the workstation;
3. is reachable when brys and oams are both offline (etra is the always-on node);
4. has a versioned backup in Nextcloud, produced by a one-way job;
5. is the live path for `pass`, the rosec store and the KeePass DB, so the Nextcloud tree is no
   longer on the boot path.

## Requirements

1. **Present at boot.** The folder sits on a persistent path and is available before `rosec` and
   `nextcloud-client` start. On brys (tmpfs home, impermanence) it must live in a `usr/data` or
   `sys/state` bucket and be bind-mounted or symlinked into the home. See
   [docs/nixos-containers.md](../nixos-containers.md) for the bucket rules.
2. **One sync engine per file.** The live folder is outside the Nextcloud tree. Nextcloud holds a
   snapshot, not a second bidirectional copy.
3. **Encryption at rest is unchanged.** `pass` stays GPG-encrypted, rosec items stay sops-encrypted.
   Syncthing transport is TLS and device IDs are pinned; no plaintext passes through Nextcloud.
4. **Conflict policy.** Syncthing file versioning plus the existing `rosec-conflicts` report; one
   documented procedure for resolving a conflict.
5. **The age identity is not synced.** `~/.config/sops/age/rosec-keys.txt` is derived from the
   YubiKey by `rosec-keys.service`; it must be regenerated per host. The sops-encrypted
   `.rosec-store-identity.sops.yaml` is synced instead.
6. **Etra is a full node.** It keeps a complete copy and can serve it while brys and oams are both
   offline. It also runs the backup job.
7. **Restorable.** A restore runbook rebuilds a host, points the three paths at the folder, unlocks
   rosec and logs in to Nextcloud, without any manual file copy.

## Candidate items

| Candidate                              | Current location                              | Size    | Sync? | Why                                                                                                                                     |
| -------------------------------------- | --------------------------------------------- | ------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `pass` store                           | Nextcloud `important/password-store`          | ~1 MB   | **yes** | The KeePass wrapper and many scripts read it at login.                                                                                  |
| rosec store (`rosec-storage`)          | Nextcloud `important/rosec-storage`           | ~305 KB | **yes** | The Secret Service store; Nextcloud's credentials live here.                                                                            |
| KeePass database                       | Nextcloud `important/keepass/drag0nius.kdbx`  | ~1 MB   | **yes** | Opened by `keepassxc.service` at login.                                                                                                 |
| sops-nix age key (`~/.config/sops/age/keys.txt`) | host-local, restored from backup      | small   | maybe   | Needed by `sops-install-secrets`; already handled per host — syncing it would widen the blast radius.                                    |
| SSH user keys (`~/.ssh/id_*`)          | home, also in sops?                           | small   | maybe   | Needed before a password manager exists; check whether the repo already derives them from sops.                                          |
| GPG home (`~/.gnupg`)                  | home                                          | ~10 MB  | **no**  | Contains the smartcard stubs and trust DB; host-specific and large enough to mis-sync. Regenerate/import per host.                      |
| `rosec-keys.txt`                       | `~/.config/sops/age/rosec-keys.txt`           | small   | **no**  | Derived from the YubiKey; requirement 5.                                                                                                |
| rosec `config.toml`                    | `~/.config/rosec/config.toml`                 | small   | **no**  | Rendered by the module from the host options; syncing it would fight the module.                                                        |
| WireGuard/NetBird keys                 | sops                                          | —       | **no**  | Already in the secret store, not in the home.                                                                                           |

## Design sketch

- **Folder location.** `~/.secrets` on every host, backed by a persistent bucket; on brys a bind
  mount from `usr/data` (survives the tmpfs home), on oams a plain directory on the pool, on etra a
  directory on its system disk.
- **Paths.** `~/.password-store -> ~/.secrets/password-store`; rosec
  `providers.sops.path = "~/.secrets/rosec-storage"`; the KeePass aspect
  `KEEPASS_PATH = "~/.secrets/keepass"`.
- **Syncthing.** One folder ID shared by oams, brys, etra and the workstation; introduce-only off;
  file versioning `staggered`; the etra node always on. Decide whether Syncthing runs as a system
  service with a dedicated user or as the `kdn` user service.
- **Backup.** A restic (or `rclone copy --immutable`) timer on etra pushes a dated snapshot of
  `~/.secrets` to Nextcloud (WebDAV). It never writes back into the live folder.
- **Bootstrap.** A new host gets the folder from etra first (device ID pinned), then unlocks rosec,
  then logs in to Nextcloud. The Nextcloud tree is then a normal, non-boot dependency.

## Open questions

1. System Syncthing user or the `kdn` user? A dedicated user cannot read the YubiKey-derived keys;
   the `kdn` user service needs `linger` and a boot-order guarantee.
2. Does the KeePass DB belong in the folder, or is it better kept in Nextcloud and opened after
   login? The wrapper currently opens it at login.
3. Restic to Nextcloud WebDAV, or a Syncthing folder that etra snapshots into Nextcloud with
   `rclone`? Restic gives versioning and dedup; a plain copy is simpler to inspect.
4. Should the workstation be a full node (a third copy) or read-only (receive-only)?
5. What is the migration order? Move `pass` and the KeePass DB first (no cycle), then the rosec
   store, then delete the Nextcloud copies and leave a README tombstone.

## Acceptance

- A fresh brys, with the Nextcloud client logged out, can unlock rosec and log in to Nextcloud using
  only the Syncthing folder.
- Stopping the Nextcloud client does not affect `pass`, rosec or KeePass.
- With brys and oams both offline, etra still serves the folder to a new or rebuilt host.
- The Nextcloud backup restores a deleted item from a dated snapshot.
- A documented runbook covers rebuild, conflict and restore.
