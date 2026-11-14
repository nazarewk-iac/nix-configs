---
type: Task
description: Migrate the KeePassXC secret-service entries into the rosec sops file-tree store, verify them, and retire the KDBX provider.
status: open
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

- Read the KDBX **read-only** (never write it during migration).
- Map the KDBX structure to the provider's model:
  - groups → collections (`<root>/<collection>/`);
  - entries → items (`<id>.sops.yaml`) with `label`, `attributes`, `secrets`;
  - `username`, `uri`, `folder`, `tag.*` → attributes; `password`, `notes`, `totp`, protected
    custom fields, KeeAgent `private_key` → secrets;
  - entry UUID → the item's `revision`/host metadata or a comment (the provider uses opaque
    ids; keep the UUID as an attribute for traceability).
- Skip or explicitly mark entries that cannot be represented (attachments, history, recycle bin,
  TOTP seeds if the provider has no TOTP support yet).
- Verify every migrated item: decrypt, compare the secret and attributes with the KDBX source;
  a machine-readable report (counts, skipped, mismatches).
- Keep KeePassXC running until the rosec provider has served the same clients for an agreed
  period; then retire the KeePassXC unit and the KDBX from the Secret Service path (the KDBX can
  stay as a backup).

## Hard requirements

- No plaintext leaves the migration process; the source is read through the existing KeePassXC
  path (CLI `keepassxc-cli show`/`export` or the D-Bus API), the destination is written through
  the provider (or `sops` directly).
- Idempotent: re-running the migration updates existing items and does not duplicate them.
- A dry-run mode and a `--check` mode (compare, no writes).
- The migration must not disturb the live KeePassXC while it still serves clients.

## Acceptance

- All in-scope entries present in the sops store, verified one by one.
- A written report with counts and the list of skipped entries with reasons.
- The Secret Service clients work against rosec with the migrated items.
- A rollback note (keep the KDBX, re-enable the KeePassXC unit).

## References

- `rosec-sops` provider in the rosec fork (`nazarewk-iac/rosec`, `sops-provider` bookmark).
- Session journal: `.cache/agents/opencode-20261113-ses_e2933f0deffeERrdlOBc6LRMXs/poc/rosec-sops-host.md`.
- KeePassXC layout: `src/fdosecrets/`, `keepassxc-cli` (`show`, `export`).
- The KDBX path and the `kdn-keepass` wrapper in this repo.
