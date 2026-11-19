---
type: Research
description: Measurements behind the atuin key reconciliation — the fleet key is uniform, anji carries a second one, 89 server records are unreadable and old, and how to verify any of it without touching real state.
task: definition.md
authored_by: agent
timestamp: 2026-11-12T12:10:00+01:00
---

# atuin key reconciliation — measurements

All commands below were **read-only**. The one pull that touches the server ran against a copy of
the local data directory, never the real one. No login, logout, purge, push or delete was performed.

## 0. Compare keys as word lists, never as bytes

`atuin key` prints the 24-word mnemonic **with a trailing newline**; a SOPS-extracted value usually
has none. Any hash of the raw text therefore differs for identical keys, and an earlier pass of this
research drew exactly that wrong conclusion.

```sh
# correct: compare word lists
python3 - <<'PY'
import subprocess, pathlib, sys
local = subprocess.run(['atuin','key'],capture_output=True,text=True).stdout.split()
other = pathlib.Path(sys.argv[1]).read_text().split()
print(len(local), len(other), local == other)
PY
```

Inside the login unit the comparison is already safe: `"$(atuin key)" != "$(cat "$CREDS_DIR/key")"`
uses command substitution, which strips trailing newlines on both sides. The comment in that unit
about `cmp` records this same class of mistake from the shell side.

## 1. What the clients hold

`atuin 18.24.5`, sync address `https://api.atuin.sh/`, account `kdn`.

| Where                          | Same 24 words as SOPS     | Local data                              |
| ------------------------------ | ------------------------- | --------------------------------------- |
| `oams` `kdn`                   | yes                       | `history.db` empty, `records.db` empty  |
| `oams` root                    | yes                       | —                                       |
| `brys` root                    | yes                       | **16,893 records**, 63,290 history rows |
| `anji` `kdn`                   | **no** — different key    | —                                       |
| `default.unattended.sops.yaml` | — (this is the reference) | —                                       |

`brys` is the witness that matters: it holds a large synced store under the shared key, so that key
matched the account when those records were pulled.

`oams` holds **no** local data at all (0 history rows, 0 records). Nothing can be lost there by a
key change — which is also why the purge in the login unit has been harmless so far.

## 2. What the server holds

A pull in an isolated data directory (section 4) with the shared key:

| Result                                                      | Count       |
| ----------------------------------------------------------- | ----------- |
| records decrypted and stored                                | **106,731** |
| records skipped, `unexpected error decrypting CEK: bad key` | **89**      |
| distinct foreign key ids among the 89                       | **7**       |

Foreign key ids seen in the warnings (atuin exposes them per record):

```
36  k4.lid.xChHxosVBgLF2oSdzjC9J0Pg4RQBS80JwfTte5p1f-B4
19  k4.lid.zXIQRs7qfM4zt_8-uBQXPm6_0loXFqJC_ld7oqhnfm8A
13  k4.lid.gxCe4o1Xcf0YWWYWgJZEpWzUSm98aHfTdyQarCcGKIqa
11  k4.lid.1VliBdRakTtoy9vCjy3L3n58EXZ80EbpG0Y-Z3AABcLl
 4  k4.lid.nP7ONH42OLvGyxkmiT8wp9VyT1kBCUZ1PJyFf33jXMaL
 4  k4.lid.IMnghrga_amOvmHUFlW_Ff2Rn0IUH9AfagTV0OgMzgsj
 2  k4.lid.OIGMB-ws79FUVIcKH9rF4p7RCdDGQmOe4cZnn9YrjsG6
```

The record ids are UUIDv7, so each one carries its creation time in the first 48 bits. Decoding
them dates the strays without any decryption:

```python
datetime.datetime.fromtimestamp(int(uid.replace('-','')[:12], 16)/1000, datetime.timezone.utc)
```

```
oldest 2025-01-09T18:42:44Z   newest 2026-05-11T09:25:22Z
17 records in 2025, 72 in 2026, none newer than six months
```

They are the residue of earlier key experiments, consistent with the owner's recollection.

## 3. Why the error appears

The unit (`modules/universal/programs/atuin/default.nix`) is:

```sh
if [ "$(atuin key)" != "$(cat "$CREDS_DIR/key")" ]; then
  atuin logout || :
  atuin store purge
elif atuin status | grep -v 'You are not logged in' || test -s <session>; then
  exit 0
fi
atuin account login -u … -p … -k …
atuin store pull --page=5000 || :
```

Consequences:

- **A mismatched SOPS key is destructive first.** `store purge` empties the local store _before_ the
  login is attempted. On `oams` there was nothing to lose; on a machine with history this throws
  away records the server cannot return without the right key.
- **The `elif` is noisy.** `atuin status` fails with `You are not logged in to a sync server` when
  no session exists, so the unit logs an ERROR on every start even though the next branch logs in
  successfully. The unit still exits 0.
- **The message the owner saw comes from the records, not the login.** A pull decrypts what it can
  and skips the rest, which is what produces `The encryption key on this machine does not match the
data on the server`.

`oams` today: `atuin doctor` reports `auth_state: Hub (authenticated)`, a recent sync, and the
shared key — so the session and the key are fine and only the strays prompt the warning.

## 4. Safe verification technique (reusable)

`atuin store pull` writes to the data directory and `--force` wipes the local store first. To test a
key against the server without touching real state, run against a **copy** that reuses the existing
session (no login, therefore no server-side write):

```sh
P=/tmp/atuin-probe
rm -rf $P && mkdir -p $P/atuin
cp -a ~/.local/share/atuin/. $P/atuin/          # includes session, key, history.db, records.db
XDG_DATA_HOME=$P XDG_CONFIG_HOME=$P XDG_CACHE_HOME=$P atuin store pull --page=5000
```

Notes:

- The copy includes `session`, so no credentials are used and nothing is created on the server.
- `--force` is safe **only** inside such a copy; it wipes that copy's store.
- The exit status can be 1 with `Threads need the daemon: enable it … to rebuild the threads
index` — an artefact of the isolated directory (no daemon there), not a sync failure. Judge the
  result by the warnings and the row count instead:

  ```sh
  sqlite3 -readonly $P/atuin/records.db 'select count(*) from store'
  grep -c 'failed to decode' <pull log>
  ```

- Never print mnemonics into logs; compare word lists and print a boolean.

## 5. What each destructive operation would actually do

Recorded because the task may need one of them later, and each is irreversible in a different way.

| Command                        | Effect                                                                                                               |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| `atuin store purge`            | deletes **local** records (`records.db`), not history, not the server                                                |
| `atuin store push`             | re-encrypts local records with the **current** key and uploads them; this is how new foreign-key records are created |
| `atuin store pull --force`     | wipes the local store, then downloads                                                                                |
| `atuin account login -k <key>` | pins that key locally and creates a session on the server                                                            |
| `atuin logout`                 | drops the local session; the server session row stays until it expires                                               |
| server-side record delete      | the only way to remove the 89 strays; irreversible, needs the account's own tooling                                  |

There is no `atuin` subcommand that deletes a single server record by id. Removing the strays
therefore means either the server's HTTP API directly, or recreating the account. That is why the
recommendation is to leave 89 old records alone rather than take that path for cosmetic warnings.

## 6. Open questions

- Which of the 7 foreign key ids belong to `anji`'s key, and which to keys that no longer exist
  anywhere? `anji` still holds its key, so its records are recoverable there; the rest may not be.
- Why `anji` never received the shared key: its atuin is home-manager + launchd, so the NixOS
  `kdn-atuin-login-<user>` unit does not exist there. Any macOS path for that unit is unverified.
- Whether the `elif` in the login unit should be simplified so a fresh machine does not log an
  ERROR line on every boot.
