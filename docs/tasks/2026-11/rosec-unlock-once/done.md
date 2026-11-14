---
type: Solution
description: A sops-wrapped derived age identity, explicit direct/derived store modes, multi-recipient rewrap and rekey, implemented in the rosec fork and wired on oams.
task: definition.md
authored_by: agent
timestamp: 2026-11-14T23:20:00+01:00
---

# Solution

## Shape

The store has two modes, recorded in `<store>/.rosec-store.yaml` and fixed at creation:

- `direct` — item files are encrypted to the unlock keys (the old behaviour).
- `derived` — item files are encrypted to a derived age identity; that identity is stored as a
  **sops-encrypted master** `<store>/.rosec-store-identity.sops.yaml` whose recipients are the
  unlock group. A plaintext sidecar `.rosec-store-identity.recipient` holds the derived public key.

The master is a normal sops file (`identity: AGE-SECRET-KEY-1…`). Its creation rule in the store
`.sops.yaml` can use `age:`, `pgp:`, `kms:`, `hc_vault:`, so the unlock group supports any sops
mode. The master rule must be first; the item rule follows and names the derived recipient.

Unlock decrypts the master once (`sops -d --extract '["identity"]'`), writes the identity to
`$XDG_RUNTIME_DIR/rosec/store-identity.age` (0600), and points the provider's `sops` calls at it.
`lock` removes the runtime file. Item operations then run with zero YubiKey access.

## Operations

- `store init --mode direct|derived` — write the explicit mode. No default; a store without it is
  refused.
- `store migrate --from <src> --to <dst>` — the only supported mode change; copies items and
  collection metadata, refuses unresolved conflicts and a populated destination.
- `identity init` — generate the derived identity, encrypt the master to the `.sops.yaml` master
  rule, write the sidecar.
- `identity show` — recipient, master path, runtime state.
- `identity rewrap` — re-wrap the master to the current rule. Add a key: add its recipient, rewrap.
  Remove: remove the recipient, rewrap (add the new key first; never remove the last usable one).
- `identity rekey` — rotate the derived identity and re-encrypt every item; the true revocation for
  a removed key that may have cached the old identity.
- `identity migrate` — a derived store whose items are still direct.

## oams store

The previous direct store was moved to `~/.local/state/rosec/direct-backup-20261114` and adopted
with `store init --mode direct`. A new `derived` store was created at the same path:

- master rule recipients: `yk-oams-unattended` and `yk-brys-unattended`;
- derived recipient: `age1v4y8577rs8374lu4lfw7sgpq9mu8acd0q0zel4aygtfsvcj7zy3sdmy6e9`;
- `store migrate` copied `default/_meta.sops.yaml`;
- the local unlock key is `~/.config/sops/age/rosec-keys.txt` (the oams slot-3 identity only).

Live proof on the private bus: the unwrap costs **1** `age-plugin-yubikey` call, the item decrypt
costs **0**, the runtime file is mode 0600, `lock` removes it, and `secret-tool store/lookup/clear`
round-trips. The daemon stays `enable = false` until the KeePassXC migration; KeePassXC still owns
`org.freedesktop.secrets`.

## Key generation

`rosec-keys.service` runs `age-plugin-yubikey --identity --slot 3` — the same generator the
sops-nix setup uses — and merges the identities into `~/.config/sops/age/rosec-keys.txt` with
`sort -u`, the sops-nix pre-start pattern as a user-owned service. It runs at login and when a USB
device node appears or disappears (`rosec-keys.path` watches `/dev/bus/usb`); after a key swap,
`systemctl --user start rosec-keys`. The full `keys.txt` stays untouched (three identities, three
plugin calls); the rosec file keeps only slot 3 (one plugin call). The brys key is added when it is
plugged in and the service runs again.

## Fork and tests

The fork `main` is `a6bd026dd4bcdaef14a23ae74298a6827cf763e0`. All new code lives in `rosec-sops/`
(`store_mode.rs`, `identity.rs`, `identity_cli.rs`, `store_migrate.rs`, tests). The upstream-touched
surface stays `Cargo.toml`, `rosecd/Cargo.toml`, `rosecd/src/main.rs`, `Cargo.lock`; `rosec-core`
is untouched. `cargo test -p rosec-sops` (110 tests), clippy, fmt, and `nix build .#rosec` pass.

The `StoreCache` bug where `_meta.sops.yaml` was cached under one type and requested as another is
fixed by keying the cache on `(path, type)`.

## Residual risks

- The runtime identity is a session-lifetime secret on tmpfs. `lock` removes it; a crash leaves it
  until logout, and the next start reuses it without an unwrap. This is the deliberate trade.
- `.sops.yaml` rule order is load-bearing. Sops uses the first matching rule; a hand edit that puts
  the item rule first encrypts the master to the wrong recipients. Tested and documented, but a
  user can still lock themselves out.
- `identity rekey` and `store migrate` are not atomic across the whole store. An interrupted run
  reports per file and is not rolled back.
- An existing store needs one `store init --mode direct|derived` before the new provider unlocks
  it. This is documented in `docs/rosec.md`.
- The brys YubiKey can unlock on oams once it is plugged in and `rosec-keys` runs; the service
  adds its slot-3 identity. The master already lists its recipient.
- `serde_yaml 0.9.34+deprecated` remains; the swap is a pre-upstream-PR task, not a blocker.
