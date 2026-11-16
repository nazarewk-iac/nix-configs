---
type: Task
description: Migrate the KeePassXC secret-service entries into the rosec sops file-tree store, verify them, and retire the KDBX provider.
status: done
authored_by: agent
timestamp: 2026-11-14T20:45:00+01:00
---

# Migrate KeePassXC secret-service content to rosec

Follow-up to `secret-service-backend`. The target provider is the native `rosec-sops` store: one
`sops`-encrypted YAML file per item under
`~/Nextcloud/drag0nius@nc.nazarewk.pw/important/rosec-storage/`, with the YubiKey age identity as
the unlock factor and `ssh_fuse = false`.

KeePassXC 2.8.0 currently serves `org.freedesktop.secrets` on this host from
`~/Nextcloud/.../keepass/drag0nius.kdbx` (never-locked regime, master password from the pass
store). The migration moves the secrets that matter for the Secret Service clients (libsecret,
`secret-tool`, git credential helpers, `gh`, editors) into the sops store.

## Scope

The source is the **live Secret Service**, not the whole KDBX. Measured on 2026-11-16: the
`org.freedesktop.secrets` collection exposes **46 items**, and all 46 live in the KDBX group
`drag0nius/secret-service`. The other ~985 KDBX entries are the personal vault (bank cards, CVVs,
TOTP, notes, logins); the Secret Service never exposes them, so they stay in KeePassXC.

- Read the live Secret Service **read-only** through D-Bus (`Item.Attributes`, `Item.Secret`), and
  never write the KDBX.
- Map one live item to one provider item: `label` from `Title`, **every public attribute copied
  verbatim** (they are the clients' search contract and are already public on D-Bus), and the raw
  secret bytes as the `password` secret.
- Keep the `Uuid` attribute as the idempotency key: a re-run deletes the previous copy by `Uuid` and
  imports again.
- Verify every migrated item through the same client interface (`secret-tool lookup`, `Item
  .Attributes`) and write a machine-readable report (counts, mismatches — never a secret value).
- Keep KeePassXC running until the rosec provider has served the same clients for an agreed period;
  then hand `org.freedesktop.secrets` to rosec and keep the KDBX as a backup for the vault.

A follow-up task decides the future of the personal vault; this task does not move it.

## Hard requirements

- No plaintext leaves the migration process: the source is read through the live D-Bus API
  (`Item.Attributes` + `Item.Secret` via `secret-tool`), and the destination is written through the
  provider (`rosec item import`). No intermediate plaintext file.
- Idempotent: re-running the migration updates existing items and does not duplicate them.
- A dry-run mode and a `--check` mode (compare, no writes).
- The migration must not disturb the live KeePassXC while it still serves clients.

## Acceptance

- All 46 in-scope items present in the sops store, verified one by one through the client interface.
- A written report with counts and mismatches; no secret value in the report.
- The Secret Service clients work against rosec with the migrated items.
- A rollback note (keep the KDBX, re-enable the KeePassXC unit).

## References

- `rosec-sops` provider in the rosec fork (`nazarewk-iac/rosec`, `sops-provider` bookmark).
- Session journal: `.cache/agents/opencode-20261113-ses_e2933f0deffeERrdlOBc6LRMXs/poc/rosec-sops-host.md`.
- KeePassXC layout: `src/fdosecrets/`, `keepassxc-cli` (`show`, `export`).
- The KDBX path and the `kdn-keepass` wrapper in this repo.
