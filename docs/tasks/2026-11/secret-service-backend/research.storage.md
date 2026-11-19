---
type: Research
description: On-disk form of each Secret Service candidate — encryption, file tree vs single file, sync behaviour with Nextcloud/Syncthing/litestream, and how a sops/age helper unlocks it.
status: open
authored_by: agent
timestamp: 2026-11-14T01:05:00+01:00
---

# Storage and sync of the candidates

Task requirements recap: encrypted at rest (a stolen disk, a synced folder or a backup
must be useless without the unlock material); file-tree storage is a bonus; no lock
file that breaks Syncthing; no single mutable SQLite file unless `litestream` is the
replication mechanism; low-tech recovery (bring a machine up from the synced copy +
the unlock material, no export step); an external `sops`/`age` (+ YubiKey/TPM2) helper
must be able to authorise the unlock.

## Summary

| Candidate                                  | On disk                                                                                                                                                                            | Encrypted?                                                                                                                                  | Shape                                                           | Sync (Nextcloud / Syncthing / litestream)                                                                                                                                                                                                                                                       | Helper unlock                                                                                                                                                                                                                                                                                  |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **rosec (local provider)**                 | `<id>.vault` (JSON: wrapped key entries + AES-256-CBC ciphertext + HMAC), `<id>.vault.meta` (labels + attribute **hashes**, non-sensitive), `<id>.vault.lock` (0-byte fcntl lease) | yes: PBKDF2-HMAC-SHA256 (200k iters default) wraps a random vault key; AES-256-CBC + HMAC-SHA256 integrity; only the wrapped key is on disk | single file + 2 small sidecars; no sqlite                       | **Syncthing/Nextcloud: yes** — docs name Syncthing/rsync explicitly (`rosec provider attach --path`). The `.lock` is 0 bytes and inert when copied. **Single-writer**: after an external replacement the local writer refuses to save until lock+unlock (revision check)                        | `AuthProviderFromPipe` (fd), `SSH_ASKPASS`, custom `[prompt] backend`, or PAM; key wrapping accepts multiple passwords                                                                                                                                                                         |
| **gopass secret-service** (1.17.4 and gss) | gopass store `$XDG_DATA_HOME/gopass/stores/root/secret-service/{_aliases.age,<collection>/{_meta.age,i<hex>.age}}`; age keyring at `~/.config/gopass/age-keyring.age`              | yes: age-encrypted per-file; the age keyring is age-encrypted (or hardware-plugin protected since 1.17.4)                                   | **file tree, one file per secret** — the task's preferred shape | **Syncthing/Nextcloud: yes with the `fs` backend** (docs: the fs backend is the documented route for Dropbox/Drive/Syncthing; gitfs+gogit also possible). No gopass lock files. Writes are direct `os.WriteFile` (no temp+rename) — torn-write risk on abnormal death is a documented PoC check | **age is the seam**: `age-plugin-yubikey` documented first-class; TPM "by mechanism, untested"; keyring-envelope (`age.keyring-identities`, v1.17.4) supports hardware plugins; `GOPASS_AGE_STDIN_PASSPHRASE` for scripted passphrases; age-agent socket protocol documented for third parties |
| **oo7**                                    | `$XDG_DATA_HOME/keyrings/v1/<name>.keyring` — gnome-keyring-compatible binary (header `GnomeKeyring`, GVariant items; attribute-name→HMAC map + AES-128-CBC+HMAC blobs)            | yes: PBKDF2-SHA256 (≥100k) → AES-128-CBC + HMAC-SHA256; 0.7.0+ supports opt-in unencrypted keyrings (do not use)                            | single file per keyring; no sqlite                              | **copy-file sync** (same class as KDBX): single-writer, last-write-wins; no lock files                                                                                                                                                                                                          | start-time only: `--login` stdin, helper socket, PAM, systemd-creds (TPM2 via homed)                                                                                                                                                                                                           |
| **KeePassXC 2.8.0**                        | one `.kdbx` (KDBX4: AES-256/Twofish/ChaCha20 + Argon2d/id; whole entry tree inside)                                                                                                | yes                                                                                                                                         | single file                                                     | **Syncthing/Nextcloud: yes, doc-endorsed** (DatabaseOperations.adoc:44 names Nextcloud and Syncthing; recommends a backend with version history); no lock file; atomic safe saves; last-write-wins, GUI Merge to reconcile; NFS caveat (#9125)                                                  | sops/age helper decrypts the **KDBX master password** (and keyfile) → `--pw-stdin`; YubiKey challenge-response is attended-only (touch), no TPM                                                                                                                                                |
| **grimsteel/pass-secret-service**          | `<store>/secret-service/` — one `<id>.gpg` per item + **plaintext** `collections.redb`/`attributes.redb` metadata (issue #12)                                                      | secrets yes (gpg); **metadata no**                                                                                                          | file tree for secrets; sqlite-like (redb) for metadata          | pass tree is Syncthing/git-friendly; the plaintext redb metadata is the wart (issue #12). A fork would move metadata into the encrypted file                                                                                                                                                    | gpg today; the `SecretStore` trait is where an age/sops helper plugs in (fork)                                                                                                                                                                                                                 |
| **mdellweg/pass_secret_service**           | `<store>/secret_service/` — `.properties`/`.aliases` plaintext JSON + `.gpg` items                                                                                                 | secrets yes; metadata no                                                                                                                    | tree + plaintext JSON                                           | pass tree syncable; plaintext metadata                                                                                                                                                                                                                                                          | hardwired gpg through pypass — **cannot use age/sops**                                                                                                                                                                                                                                         |
| **yousefvand**                             | single `db.json` (+ `config.yaml`)                                                                                                                                                 | optional AES-256-GCM keyed by a raw 32-char `MASTERPASSWORD` env var (**no KDF**)                                                           | single JSON blob                                                | syncable as one file; no lock                                                                                                                                                                                                                                                                   | env var only                                                                                                                                                                                                                                                                                   |
| **bitw**                                   | none locally (vault is remote)                                                                                                                                                     | n/a                                                                                                                                         | n/a                                                             | n/a                                                                                                                                                                                                                                                                                             | n/a                                                                                                                                                                                                                                                                                            |

## What each sync transport can do with the chosen layouts

- **Nextcloud / Syncthing** — work for **all** single-file (rosec vault, oo7 keyring,
  KDBX) and **tree** (gopass, pass, grimsteel secrets) layouts. The file-tree layouts
  have the nicer properties the task asks for: a human can inspect the tree (ciphertext
  only), per-file conflicts are rare, and a lost file loses one secret, not the store.
  The single-file layouts carry the "two writers clobber each other" risk; both rosec
  (revision check) and KeePassXC (GUI Merge) have a recovery path, but the correct
  operating rule is one writer at a time.
- **litestream** — only relevant for sqlite-shaped stores. **No candidate here needs
  it**: none of the viable routes stores the secret material in SQLite (grimsteel's
  redb is not sqlite and holds only metadata; rosec/gopass/KeePassXC/oo7 have no
  sqlite at all). So litestream drops out of the decision.
- **Lock files** — none of the viable candidates writes an app-level lock file with
  content. rosec's `.lock` is a 0-byte fcntl lease (a synced copy is inert);
  KeePassXC/oo7/gopass create none. This satisfies the "no lock file that breaks
  Syncthing" requirement for every route except the general git `index.lock` during a
  concurrent gopass git operation.

## The sops/age + YubiKey/TPM2 helper, per layout

The task's requirement 5: the helper decides whether the YubiKey, the TPM or both
authorise the unlock, and the daemon receives an already-unlocked plaintext view or a
key. Measured on this host: `sops` 3.13.3 + `age` 1.3.2 + `age-plugin-yubikey` 0.5.1
with a plugged YubiKey 4/5 decrypt a real repo sops file with no touch and no PIN
(slot 3 policy). So the helper exists and works.

| Layout         | Helper input                                                                                                                                                                | Helper → daemon channel                                                                                                                                          |
| -------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| rosec vault    | a password string that is itself sops-encrypted; the helper runs `sops -d` (age recipient = the YubiKey age identity) and pipes the result                                  | `busctl --user call … org.rosec.Daemon AuthProviderFromPipe <id> <fd>` (the PAM helper's own channel), or `SSH_ASKPASS=<helper>`, or `[prompt] backend=<helper>` |
| gopass tree    | the age identity (a YubiKey age identity) unlocks the store directly — no separate password needed; or the keyring passphrase via `sops -d` → `GOPASS_AGE_STDIN_PASSPHRASE` | gopass itself invokes `age-plugin-yubikey` (touch = the hardware prompt); the daemon never sees the key                                                          |
| oo7 keyring    | sops-encrypted keyring password, or a systemd credential (`ImportCredential`, TPM2 via homed)                                                                               | `sops -d                                                                                                                                                         | oo7-daemon --login` as the unit's ExecStart; or the helper socket   |
| KeePassXC KDBX | sops-encrypted KDBX master password (and keyfile)                                                                                                                           | `sops -d                                                                                                                                                         | keepassxc --pw-stdin <db>` at service start; no mid-session channel |
| grimsteel fork | the fork's `SecretStore::read_secret` execs the helper (age/sops decrypt of the per-item file)                                                                              | in-process; `can_prompt` threads headless fail-fast                                                                                                              |

The one structural difference: **gopass and rosec can both be unlocked by a hardware
age identity** (the same `age-plugin-yubikey` mechanism this host already uses for
sops), while **oo7 and KeePassXC need the helper to produce a password string at
start**. The first class keeps the secret material inside the daemon's own crypto;
the second class pipes a password. Both satisfy "the helper decides", but the age
route has fewer copies of the secret in process memory outside the store's own crypto.

## One store for all hosts — what is shared and what is per-host

Question: can a single synced store serve several hosts? Answer: **yes for the secret
material, no for the unlock material by default** — the store is host-independent, the
age keyring is not.

| Piece                                                                | Location                                                         | Travels with the synced store?                                                                                                                                 |
| -------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| gopass store tree (items, `_aliases.age`, `_meta.age`)               | `$XDG_DATA_HOME/gopass/stores/root/secret-service/…`             | **yes** — paths and names are store-relative, not host-relative                                                                                                |
| secret-service item paths (`secret-service/<collection>/i<hex>.age`) | inside the store                                                 | **yes** — the same collection/item names exist on every host                                                                                                   |
| `session` (volatile) collection                                      | Linux kernel keyring, per host                                   | **no, by design** — never written to the store (ADR A-11)                                                                                                      |
| gopass **age keyring** (`age/identities`)                            | `$XDG_CONFIG_HOME/gopass/age/identities` — **outside** the store | **no** — each host needs its own copy of the keyring/identity, unless `age.keyring-identities` points at a shared (synced or hardware) plaintext identity file |
| daemon metadata cache                                                | daemon memory                                                    | n/a — restart the daemon after an out-of-process write (sync)                                                                                                  |
| rosec vault                                                          | `<id>.vault` + `<id>.vault.meta` + `<id>.vault.lock`             | **yes** (single writer; the `.lock` copy is inert)                                                                                                             |
| KeePassXC                                                            | one `.kdbx`                                                      | **yes** (last-write-wins; Merge to reconcile)                                                                                                                  |
| oo7                                                                  | `$XDG_DATA_HOME/keyrings/v1/<name>.keyring` per keyring          | yes as a file, but the directory is per-host by default — sync that file explicitly                                                                            |

Practical rules for a shared store:

1. Sync the **store tree** (gopass `fs` backend, or git without `core.autosync`), not
   the host config dir.
2. Give every host an unlock path: either its own keyring copy, or — better — a shared
   plaintext identity file pointed to by `age.keyring-identities` (this file may hold
   `AGE-PLUGIN-YUBIKEY-…` identities, i.e. the hardware factor).
3. One writer at a time. gopass has no store lock; per-file writes are small but not
   atomic (`os.WriteFile`), so simultaneous edits can tear a file. Prefer git sync
   (one commit per operation) over raw file sync, or accept the risk on the `fs`
   backend.
4. Restart the daemon after a sync that changed items out of process; its metadata
   cache is process-local (ADR limitation 3).
5. Never sync the kernel-keyring `session` collection — it is not on disk.

The PoC exercises exactly this: it copies the store tree to a second “host” (fresh
`XDG_DATA_HOME`, same identity) and reads the same item back; a second host without
the identity fails to decrypt, which confirms the keyring is the only per-host piece.

## Low-tech recovery check

- rosec: copy the `.vault` file to a new machine, `rosec provider attach --path`,
  unlock with the same password (or the sops helper). `rosec vault snapshot restore`
  exists for snapshots. ✅
- gopass: clone/copy the store tree + the age identity (or the YubiKey), run gopass.
  ✅ (docs also note the encrypted keyring can be decrypted with the standard `age`
  CLI — an escape hatch that does not need gopass)
- oo7: copy the `.keyring` file + the password/credential. It is
  gnome-keyring-compatible, so even gnome-keyring can read it as a last resort. ✅
- KeePassXC: copy the `.kdbx` + password/keyfile; any KeePass client can open it. ✅
- grimsteel fork: the fork must keep the "file tree + plain helper" property; a
  half-encrypted metadata store would break it (issue #12 is the warning). ⚠️

## Verdict on the storage requirement

Every route satisfies "encrypted at rest" and "sync without a conflicting lock file".
On the task's _preferred_ shape — a file tree, one file per item — **gopass is the only
ready-made candidate that stores the secret material as a per-item encrypted file
tree**; rosec/oo7/KeePassXC are single-file stores. On the _helper_ requirement,
**gopass and rosec are the two that can be unlocked by a hardware age identity with
no password string anywhere**; oo7/KeePassXC need a start-time password.
