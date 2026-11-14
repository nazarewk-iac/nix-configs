---
type: Research
description: Per-candidate automated SSH key route — agent socket, what starts and unlocks it, key types served, allowed_signers, and the proof commands.
status: open
authored_by: agent
timestamp: 2026-11-14T01:20:00+01:00
---

# Automated SSH key loading — per candidate

Task requirement recap (the "Angle"): the service should feed an SSH agent with **no
interactive `ssh-add`**, headless, with the key material coming from the same
`sops`/`age`/YubiKey path that unlocks the store; locking the service (or removing a
key's item/tag) revokes the key; commit verification needs an `allowed_signers` file
that follows the same lock state. Two routes are acceptable: the provider's own agent,
or an independent agent fed from the store.

This tree already runs a FIDO2-capable OpenSSH agent (`services.ssh-agent` from the
`ssh-agent` aspect, `pkgs.openssh` linked with `libfido2`) and signs commits through
`kdn-signing`, so a candidate that also feeds that agent is worth more than one that
cannot.

## Summary

| Candidate                                    | Own agent?                                              | Socket                                                                                                        | Started by                                                           | Unlocked by                       | Key types                                                                                                                                   | Revoked on lock?                                                  | `allowed_signers`                                                                                       |
| -------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **rosec**                                    | ✅ built-in                                             | `$XDG_RUNTIME_DIR/rosec/agent.sock` (source `rosecd/src/ssh.rs`; README path `rosec/ssh/agent.sock` is stale) | `rosecd` at startup (`ssh_fuse=true` default; degrades without FUSE) | provider unlock/sync events       | ed25519, RSA, ECDSA, DSA, encrypted PEMs; **no sk-ssh, no certificates**; `ssh-add` Add/Remove/Lock protocol commands unsupported by design | ✅ keys removed immediately from agent + FUSE; key store zeroized | ✅ generated in the FUSE tree (`custom.ssh_signing_principal`), **fail-closed**: unreadable when locked |
| **gopass** (both daemons)                    | ❌                                                      | —                                                                                                             | —                                                                    | —                                 | —                                                                                                                                           | —                                                                 | ❌ (generate from the pub key)                                                                          |
| **oo7**                                      | ❌ (grep-verified: no ssh code at all)                  | —                                                                                                             | —                                                                    | —                                 | —                                                                                                                                           | —                                                                 | ❌                                                                                                      |
| **KeePassXC 2.8.0**                          | ❌ (it is a **client** of `$SSH_AUTH_SOCK` since 2.3.0) | uses the running agent's socket                                                                               | DB unlock triggers autoload of entries with SSH-agent settings       | DB unlock                         | ed25519/RSA/ECDSA (+ in-DB keygen), **sk-ssh CTAP2 provider since 2.8.0**; no CLI control                                                   | ✅ revoke on DB lock (except gpg-agent, which cannot remove keys) | ❌ (keys live in the external agent; generate from `ssh-add -L`)                                        |
| **grimsteel / yousefvand / mdellweg / bitw** | ❌                                                      | —                                                                                                             | —                                                                    | —                                 | —                                                                                                                                           | —                                                                 | ❌                                                                                                      |
| **gnome-keyring** (reference)                | ✅ (its own ssh component)                              | `$XDG_RUNTIME_DIR/keyring/ssh`                                                                                | gnome-keyring daemon                                                 | login keyring unlock (GUI prompt) | RSA/ed25519                                                                                                                                 | partial                                                           | ❌                                                                                                      |

## Route 1 — the provider's own agent: rosec

This is the only candidate with a real, automated, headless agent. Details from
`rosec.md` §7 (source paths there):

- **What starts it:** `rosecd` itself at startup (`SshManager::start()`), independent
  of any login shell. If it cannot start, the daemon continues without SSH support
  rather than aborting.
- **What unlocks it:** provider unlock events. Keys are populated from provider items
  at unlock and cleared on lock, autolock timer, logout, sleep and shutdown.
- **What it serves:** `RequestIdentities` and `SignRequest` only (the `ssh-agent-lib`
  `Session` trait); everything else returns `UnsupportedCommand` by design — keys are
  vault-driven, "no manual `ssh-add`".
- **Key sources:** native `sshkey` items (`rosec item add --type=ssh-key
--generate-ssh-key` mints ed25519), PEM scan of `notes`/`password`/custom fields on
  any item, and KeePassXC KeeAgent attachments.
- **Limits that matter here:** **no FIDO2 `sk-ssh` resident keys** (the FIDO2 feature
  is WebAuthn passkeys, unrelated), **no certificates**, no `ssh-add` protocol
  commands. For this tree that is acceptable: the FIDO2-capable agent already exists
  (`kdn.home.ssh-agent`), and rosec would serve the _software_ keys from the vault.
- **Headless signing confirmation:** if per-key `ssh_confirm=true` is set, the
  confirmation is a GUI dialog, a TTY `Allow / Deny [y/N]` prompt, or — with neither
  display nor TTY — **allowed with a warning in the log** (docs/ssh-agent "Signing
  confirmation"). That is the only path in any candidate that explicitly decides the
  no-display case.
- **FUSE tree** (read-only, in-memory, at `$XDG_RUNTIME_DIR/rosec/ssh/`):
  `keys/by-name/<item>.pub`, `keys/by-fingerprint/<sha256>.pub`,
  `keys/by-host/<host>.pub`, `config.d/<provider>-<item>.conf` (`Host` blocks with
  `IdentityFile`/`IdentityAgent`/`IdentitiesOnly yes`), and the root
  `allowed_signers` synthesized from `custom.ssh_signing_principal` tags. Without
  `/dev/fuse` the agent socket still works; only the FUSE tree disappears (the PoC
  generates the equivalent `allowed_signers` line by hand if FUSE is unavailable).

Proof commands (docs + source; the PoC must reproduce them):

```sh
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/rosec/agent.sock"   # source path, not the README one
ssh-add -l                                                 # lists vault keys, no ssh-add was run
ssh -o IdentitiesOnly=yes git@github.com                   # authenticates with the vault key
ssh-keygen -Y sign -f <(ssh-add -L | head -1 | awk '{print $2}') -n git message.txt
git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$XDG_RUNTIME_DIR/rosec/ssh/allowed_signers" \
    commit -S -m 'signed from the vault'
git log --show-signature -1
# lock the provider, then:
ssh-add -l                                                 # key gone
cat "$XDG_RUNTIME_DIR/rosec/ssh/allowed_signers"           # fail-closed: empty/unreadable
```

## Route 2 — an independent agent fed from the store

For candidates with no agent, the acceptable route is: OpenSSH `ssh-agent` (already
running here as `ssh-agent.service`) plus a small **feeder** that extracts the key from
the store after the store unlock and calls `ssh-add`. This is automated (the feeder is
a systemd user service or an ExecStartPost of the unlock unit), headless (no TTY), and
the key is in the agent only while the store is unlocked. What each store offers for
this:

- **gopass** — the cleanest feeder material: the key is a normal gopass secret, so
  `gopass cat <path>` (raw content to stdout; `-c` is the clipboard flag and `-o` truncates multi-line keys) or the documented
  `gopass env <prefix> --file` (ramdisk temp file, `KEY_FILE` env) feeds
  `ssh-add`. **No FIDO2 and no allowed_signers** — generate the latter with
  `ssh-keygen -y -f <key>` → `principal ssh-ed25519 AAAA...`. Lock semantics: the
  feeder must also run `ssh-add -D` (or remove the one key) on store lock; gopass
  itself has no agent to revoke from.
- **oo7** — keys can live as items in the keyring; a feeder reads them with
  `oo7-cli`/`secret-tool` at daemon unlock and calls `ssh-add`. Same lock caveat as
  gopass.
- **KeePassXC** — needs **no feeder**: it already speaks the agent protocol to
  `$SSH_AUTH_SOCK` and autoloads/revokes on DB unlock/lock. It is route 2 done
  natively, with the DB (never-locked regime, see
  [research.headless.md](research.headless.md)) as the unlock source.
- **grimsteel fork** — the daemon has no SSH code; a feeder reading the pass tree is
  the route, same shape as gopass.

Proof commands for the gopass feeder (design; all pieces exist):

```sh
# one-shot feed at store unlock (systemd user service)
install -m600 /dev/null /run/user/$UID/id_ed25519
gopass cat secret-service/ssh/id_ed25519 > /run/user/$UID/id_ed25519
ssh-add -t 8h /run/user/$UID/id_ed25519 && shred -u /run/user/$UID/id_ed25519
ssh-add -l
# allowed_signers from the same item
printf '%s %s\n' "$(git config user.email)" "$(ssh-keygen -y -f <(gopass show -c secret-service/ssh/id_ed25519))" \
  > "$XDG_RUNTIME_DIR/allowed_signers"
```

## Requirement-by-requirement verdict

- **Automated (no interactive ssh-add):** rosec ✅ (keys appear at unlock);
  KeePassXC ✅ (autoload); gopass/oo7 ✅ only with a feeder service; others ❌.
- **Headless:** rosec ✅ (explicit no-display policy, TTY prompt exists but is not
  required); KeePassXC ✅ (autoload is not a prompt); feeder ✅ (no TTY).
- **Non-interactive consumers (`git` over SSH, `git commit -S`, scripts):** rosec ✅
  (`SignRequest`; `git commit -S` with `gpg.format=ssh`); KeePassXC ✅ (external
  agent does the signing); feeder ✅.
- **No plaintext key at rest:** all ✅ — the key is encrypted in the store and only
  in agent memory while unlocked. The feeder's temporary file is the weak point
  (mitigate: ramdisk + `0600` + shred, the `gopass env --file` pattern).
- **Lock semantics:** rosec ✅ (immediate revocation + zeroize); KeePassXC ✅ (revoke
  on lock; caveat: gpg-agent cannot remove keys); feeder ⚠️ (the feeder must implement
  the revoke — `ssh-add -D` — itself).
- **`allowed_signers` follows lock state:** rosec ✅ (FUSE, fail-closed); others ⚠️
  (generate at unlock; delete on lock — a unit's job).

## Recommendation for the SSH angle

- If rosec is the chosen provider: **use its agent for software keys, keep the
  existing FIDO2 agent for hardware keys**, and use the FUSE `allowed_signers` for
  verification. This satisfies the angle without writing any new service.
- If gopass is the chosen provider: add a **feeder service** (≈50 lines: unlock →
  `gopass show` → `ssh-add`; lock → `ssh-add -D`; regenerate `allowed_signers`), and
  keep the existing FIDO2 agent for hardware keys. The angle is satisfied, but with
  local code.
- KeePassXC (the incumbent): already satisfies the angle through the external agent;
  no new code.
