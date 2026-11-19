---
type: Task
description: Every machine but anji runs the same atuin encryption key, and 89 old records on the server belong to other keys; decide how to converge anji and what to do with the strays.
status: open
authored_by: agent
timestamp: 2026-11-12T12:10:00+01:00
---

# Converge the fleet on one atuin encryption key

## Context

Atuin keeps shell history and syncs it to `https://api.atuin.sh/` under the account `kdn`. The
repo drives it from two places:

- `modules/universal/programs/atuin/default.nix` — settings, the daemon, a ZFS workaround, and a
  `kdn-atuin-login-<user>` unit that logs in from SOPS and pulls at boot.
- `default.unattended.sops.yaml` — `atuin.username`, `atuin.password` and `atuin.key`.

The login unit compares the local key with the SOPS key. When they differ it runs
`atuin logout`, `atuin store purge` and then `atuin account login -k <SOPS key>`. A wrong SOPS key
therefore **destroys local records first**, and only then fails to decrypt the account's data.

## Problem

`oams` shows:

```
The encryption key on this machine does not match the data on the server
```

Two separate things are behind that message, and only one of them is a machine holding a wrong key.

## Finding

**The key itself is consistent.** `oams` (`kdn` and root), `brys` root and
`default.unattended.sops.yaml` all hold the _same_ 24-word mnemonic. Compare them as word lists,
never as byte strings or hashes: `atuin key` ends with a newline, the SOPS value does not, so every
hash of the raw text differs even when the keys are identical.

| Where                     | Same as SOPS                     |
| ------------------------- | -------------------------------- |
| `oams` `kdn`, `oams` root | yes                              |
| `brys` root               | yes                              |
| `anji` `kdn`              | **no** — a different 24-word key |

**The account's data belongs to the shared key.** A read-only pull against a _copy_ of the local
state decrypted **106,731** records with it. Only **89** records failed, spread over **7 foreign
key ids**, and every one is old: `2025-01-09` to `2026-05-11`, none newer than six months.

So this is not a lost-key disaster, and it is not a SOPS problem. It is one machine that logged in
with a key of its own (`anji`, whose atuin is home-manager + launchd and never ran the NixOS login
unit), plus 89 strays from earlier experiments.

See [research.md](research.md) for the measurements, the mechanism that created the strays, and the
safe verification technique.

## Proposed approach

No account migration, no `store purge`, no re-upload of 106k records.

1. **Bring `anji` onto the shared key.** It currently pushes history encrypted under its own key,
   which is how a machine creates records nobody else can read. Log it in with the SOPS key
   (`atuin account login -k …`, or let the fleet's login path run there once it exists for macOS)
   and then `atuin store push` so its local history is re-encrypted under the shared key.
2. **Leave the 89 strays alone** unless they become a nuisance. They cost 89
   `WARN … bad key` lines per pull and nothing else. Every removal path is irreversible:
   `atuin` has no subcommand that deletes a single server record, so it means the server's HTTP API
   or a new account. Record the decision here before deleting anything.
3. **Verify** with the isolated pull described in research.md: zero `bad key` warnings except the
   accepted strays, and no `store purge` in the unit log.
4. **Optional, small:** the login unit's `elif atuin status | grep -v 'You are not logged in'` logs
   an ERROR on every boot of a machine that has no session yet, even when the following login
   succeeds. Simplify it so a clean boot is quiet.

## Guardrails

- Compare keys as word lists. A newline, a trailing space or a hash of the raw string gives a false
  "different key" answer and would send the fleet through an unnecessary purge.
- Never run `atuin store purge` or `pull --force` against a real data directory while any doubt
  remains. Both wipe local records first.
- Never let a machine log in with a key that differs from the fleet's: every push it makes creates
  new unreadable records, which is exactly what produced the 89 strays.
- Server-side deletion of records is the only irreversible step in this task.

## Definition of done

- `atuin key` on `anji` and on every Linux host yields the same 24 words as SOPS.
- An isolated pull decrypts all records except the strays that were explicitly accepted or deleted.
- The `kdn-atuin-login-<user>` units finish without the mismatch error, and no unit logs a
  `store purge`.
