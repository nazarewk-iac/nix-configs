---
type: Task
description: Unlock the sops-encrypted rosec store once per session with a derived sops identity wrapped to multiple YubiKeys, with explicit store modes, add/remove keys and rekey.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-11-14T23:20:00+01:00
---

# rosec unlock-once derived identity

> ✅ **Done** — see the solution in [done.md](done.md).

## Context

The `rosec-sops` provider (created by the `secret-service-backend` task) decrypts each item file
with `sops`, which invokes `age-plugin-yubikey` for every identity in
`~/.config/sops/age/keys.txt`. On oams that is three identities per file, so the YubiKey LED is
active on every read and write. The store is also encrypted **directly** to the YubiKey recipient,
so there is no way to cache an unlock.

## Requirements

- One YubiKey activation per session, not per item. Item reads and writes after the unlock must not
  touch the token.
- The derived identity must itself be a **sops identity**, so the unlock group can use any sops
  mode (age/YubiKey, PGP, KMS, Vault), not only age.
- The store has exactly two modes, chosen explicitly at creation and **not changeable in place**:
  `direct` (items encrypted to the unlock keys) and `derived` (items encrypted to the derived
  identity). A store without a recorded mode is an error; there is no default.
- Multiple unlock keys: add and remove recipients on demand. Adding/removing re-wraps the master
  only; true revocation (a removed key may have cached the identity) needs a rekey that re-encrypts
  the store.
- Both the **oams** and **brys** unattended YubiKeys must unlock the store.
- A mode change is a migration into a new store, never an in-place flip.
- The existing KeePassXC Secret Service stays untouched; the daemon remains `enable = false` until
  its migration task lands.
- Tests, fork maintenance docs, and nix-configs docs.

## Acceptance

- The fork implements the two modes, the sops-wrapped derived identity, the runtime identity, the
  `identity init/show/rewrap/rekey/migrate` and `store init/migrate/show` commands.
- The oams store is `derived`, its master is wrapped to the oams and brys recipients, and one
  private-bus session proves one plugin call at unlock and zero per item.
- The module and host config expose the new options; `docs/rosec.md` documents the modes, the
  unlock flow, the key operations, and the migration.
- The full `rosec-sops` suite passes, and the fork's upstream-touched surface stays at three code
  files plus the lock.

## References

- Provider: the `rosec-sops` crate in the `nazarewk-iac/rosec` fork.
- Store guide: [docs/rosec.md](../../../rosec.md).
- Parent task: [secret-service-backend](../secret-service-backend/definition.md).
- Conflict follow-up: [rosec-conflict-resolution](../rosec-conflict-resolution/definition.md).
- Migration follow-up: [keepassxc-to-rosec-migration](../keepassxc-to-rosec-migration/definition.md).
