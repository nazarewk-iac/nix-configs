---
type: Plan
description: Migrate the 46 live Secret Service items from KeePassXC into the rosec derived sops store on oams, then hand ownership of org.freedesktop.secrets to rosec.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T21:00:00+01:00
---

# KeePassXC → rosec Secret Service migration plan (oams)

> **Scope:** the **46 items the Secret Service actually exposes**, read from the live bus and copied
> into a private `rosecd`, verified through the same client interface, then one bus owner after the
> cutover. KeePassXC keeps the personal vault and is **read-only** until the cutover.

## 0. Scope: 46 items, not the whole database

Measured on `oams` on 2026-11-16:

| Fact | Value |
| --- | --- |
| Live Secret Service items | **46** (`org.freedesktop.secrets/collection/drag0nius`) |
| KDBX entries | 1031 current (1037 incl. 6 in the recycle bin), 3237 history |
| Group holding every live item | `drag0nius/secret-service` (46/46 match by UUID) |
| What the 46 are | Element sessions (15), browser Safe Storage keys (8), IntelliJ DB/Git (5), Bitwarden tokens, Webex, Microsoft Graph, poetry, Remmina, Nextcloud app password, gh, … |
| Everything else in the KDBX | the personal vault: bank cards, CVVs, TOTP, notes, logins — **never exposed to D-Bus** |

The migration therefore moves the **Secret Service contract**, not the password database:

- **In scope:** all 46 items, all of their public attributes, and their secret bytes.
- **Out of scope:** the other 985 entries. They stay in KeePassXC. A follow-up task can decide their
  future; this plan does not touch them.
- **Consequence:** no KDBX export, no 8 MB plaintext XML, no `keepassxc-cli`, no `pass` piping, no
  `expect`, no 1031-entry mapping, no TOTP/notes/card field classification. All of that belonged to
  the wrong scope and is dropped.

## 1. Live facts (verified 2026-11-16)

| Fact | Value |
| --- | --- |
| KeePassXC | 2.8.0, `keepassxc.service` active, PID 196489, `--pw-stdin`, wrapper `kdn-keepass.sh` |
| FdoSecrets | `[FdoSecrets] Enabled=true`; the wrapper upserts `Enabled=true` at every start; the GUI runs `keepassxc %f`, **not** the wrapper |
| `secrets-service` | unit `dbus-kdn-sway-secrets-service.service`: `Type=dbus`, `BusName=org.freedesktop.secrets`, `script = sleep infinity`, `TimeoutStartSec=120s`, `partOf` the sway target |
| dependency web | `keepassxc.service` is `WantedBy` the shim; `nextcloud-client` `Requires` the shim |
| live attributes | `Title`, `UserName`, `URL`, `Notes`, `Path`, `Uuid`, plus client attributes (`xdg:schema` 34, `service` 31, `account` 18, `application`, `username`, `user`, `source`, `version`, `server`, `type`, `FDO_SECRETS_CONTENT_TYPE`, `filename`, `key`, `MsalClientID`, `explanation`, `Microsoft.Developer.IdentityService`) |
| attribute values | empty `Notes`/`URL`/`UserName` are common; no attribute carries a secret value |
| secrets | 46 read through `secret-tool lookup Uuid=<uuid>`: all non-empty, all UTF-8, no NULs, 8–10608 bytes (the 10.6 KB one is a Microsoft Graph JSON cache) |
| item object paths | unstable across cache rebuilds; address items by the `Uuid` **attribute**, never by path |
| `secret-tool lookup` | returns the raw secret with no trailing newline (byte-identical to the KeePassXC entry `Password` for 45/46; the 46th is an attachment, which is why the bus, not the export, is the source) |
| rosec store | `derived`; `default/_meta.sops.yaml` only; `age_recipient` + `identity_file`; `rosec-keys.txt` 42 bytes, slot 3 |
| rosec daemon | `enable = false`; no `rosecd` unit loaded; a fresh `rosecd` starts **locked** |
| rosec import | TOML `[item]` + **top-level** `[attributes]`/`[secrets]`; empty values dropped; `{ base64 = "…" }` for binary secrets; reserved attribute names are `id`, `label`, `created`, `modified`, `rosec:provider`, `rosec:type`, `rosec:totp` |
| rosec export | `build_item_toml` hides `rosec:`/`xdg:` attributes, so the export is **not** a fidelity check for `xdg:schema` |
| `GetSecret` | returns the first of `password`, `number`, `private_key`, `notes` that exists, else the type default; `type = "login"` → `password` |
| `rosec item import --force` | replaces only when secrets are byte-equal — **not** an upsert |
| HM | `systemd.user.startServices = "suggest"`: a switch enables units but does not start or restart them |

## 2. The tool

`hack/keepassxc-to-rosec.py` (Python 3, standard library only). Two sources and one destination, each
addressed by **bus address**, so the live and private daemons never share a bus:

```sh
python3 hack/keepassxc-to-rosec.py --from "$DBUS_SESSION_BUS_ADDRESS" --to "unix:path=$MIG/bus" \
    --dry-run|--apply|--check|--migrate --provider sops --report "$STAGE/migrate.json"
```

- **read**: `Service.Collections` → `Collection.Items` → `Item.Attributes` via
  `busctl --address <bus> --json=short`; the secret via `secret-tool lookup Uuid=<uuid>` on that bus.
  A stale path is retried (object paths are rebuilt under load).
- **write**: `rosec item delete -y Uuid=<uuid>` (fails harmlessly when absent), then
  `rosec item import --provider sops` with the TOML on stdin.
- **check**: re-reads the destination through the same client interface and compares label, every
  non-empty source attribute and the secret bytes. The report lists labels, attribute names, lengths
  and pass/fail — never a secret value.
- **`--self-test`**: round-trips quoting, unicode, a newline secret, a binary secret, an empty
  attribute, and a `:`-key.
- No plaintext file is ever written: the secrets stay in the process memory.

## 3. Mapping

| Source (live Secret Service) | Destination (rosec) |
| --- | --- |
| `Item.Label` / the `Title` attribute | `[item].label` |
| the item type | `[item].type = "login"` (so `GetSecret` picks `password`) |
| **every** attribute, verbatim — **empty values are dropped** (rosec's parser drops them: all 46 have an empty `Notes`/`URL`/`UserName`, one an empty `username`) | top-level `[attributes]`, quoted keys |
| the secret bytes | `[secrets].password`, or `{ base64 = "…" }` when not UTF-8 |
| key `Uuid` | the idempotency key |

Attributes are copied **verbatim** because they are the clients' search contract
(`secret-tool lookup xdg:schema … service …`). They are already public on D-Bus today, so the copy
adds no exposure; the plaintext conflict marker holds exactly what the bus already publishes.
`Notes` stays a public attribute because KeePassXC publishes it as one. Empty values are dropped by
rosec, so the destination holds fewer keys than the source: the check compares only non-empty source
values, and no client searches for an empty one.

## 4. Phases

### Phase 0 — preflight (read-only)

```sh
set -uo pipefail
KDBX="$HOME/Nextcloud/drag0nius@nc.nazarewk.pw/important/keepass/drag0nius.kdbx"
STAGE="$(mktemp -d -p "$HOME/.local/state/rosec" rosec-migrate.XXXXXX)"; chmod 700 "$STAGE"
sha256sum "$KDBX"
rosec-sops store show
systemctl --user is-active rosec-keys.path rosec-keys.service || true
ls -l "$HOME/.config/sops/age/rosec-keys.txt"
systemctl --user is-active keepassxc.service || true
busctl --user status org.freedesktop.secrets | head -3 || true
python3 hack/keepassxc-to-rosec.py --from "$DBUS_SESSION_BUS_ADDRESS" --dry-run --report "$STAGE/source.json"
```

Note there is no `set -e`: `systemctl status/is-active` and `busctl status` exit non-zero for an
inactive unit or a missing owner, and a preflight must not abort on them.

Checkpoint: the store is `derived`; the key file exists; KeePassXC owns the bus; the dry run reports
**46 items**, 0 binary secrets, 0 empty secrets.

### Phase 1 — start a private rosecd (no writes yet)

The private daemon must not collide with the live one, and it must not be reachable by other local
users. Remember the live address first, then point **both** client conventions at the private socket:

```sh
LIVE_BUS="$DBUS_SESSION_BUS_ADDRESS"
MIG="$(mktemp -d -p "$HOME/.local/state/rosec" rosecd.XXXXXX)"; chmod 700 "$MIG"
rosecd --socket "$MIG/bus" --no-migrate >"$MIG/daemon.log" 2>&1 &
MIG_PID=$!
for _ in $(seq 1 80); do [ -S "$MIG/bus" ] && break; sleep 0.1; done
# `rosec` resolves ROSEC_SOCKET before the session bus, and libsecret reads
# DBUS_SESSION_BUS_ADDRESS: set both, or the next commands talk to KeePassXC.
export ROSEC_SOCKET="$MIG/bus"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$MIG/bus"
rosec status
busctl --address "$DBUS_SESSION_BUS_ADDRESS" status org.freedesktop.secrets | head -3
```

- `mktemp -d` gives `0700`; a shared `/tmp/rosec-mig` would expose an unlocked bus to every local user.
- `XDG_RUNTIME_DIR` is **not** overridden. Overriding it breaks `rosec-prompt` (`NoCompositor`,
  measured in review 4) and would give the private daemon a second, separate runtime identity.
  Sharing the real runtime dir is deliberate: the unlock below writes the one runtime identity that
  the post-cutover `rosecd` reuses, so the session pays **one** YubiKey unwrap.
- `rosec status` must report the **private** daemon. If `ROSEC_SOCKET` is left unset, `rosec`
  silently uses the session bus and every later command hits KeePassXC.

### Phase 2 — unlock the private daemon

The sops provider always presents an optional password field ("No password needed — press Enter"),
and `item import` does not unlock, so the private daemon must be unlocked first:

```sh
script -qec "rosec unlock" /dev/null < <(printf '\n')   # allocates a pty; the field is optional
rosec status
```

Fallback when `script` cannot allocate a pty: `rosec unlock --gui` and press Enter in the dialog
(Wayland and `XDG_RUNTIME_DIR` are the session's own, so the prompt works).

Checkpoint: `rosec status` names the private daemon; the YubiKey blinked once; the daemon log shows
`mode=derived`. `rosec provider list` is **not** proof — it falls back to the config file when the
daemon has nothing better. The Phase 3 probe is the proof: a locked provider rejects the import with
`locked`.

### Phase 3 — probe the import shape

Validate the TOML contract on one throwaway item, **before** any real write:

```sh
rosec item import --provider sops <<'TOML'
[item]
label = "migration-schema-probe"
type = "login"

[attributes]
"Uuid" = "0000000000000000000000000000beef"
"xdg:schema" = "probe"

[secrets]
password = "probe"
TOML
rosec item export Uuid=0000000000000000000000000000beef
# `toml_key` leaves a bare TOML key bare, so the export prints `Uuid = "..."`.
rosec item export Uuid=0000000000000000000000000000beef \
    | grep -q '^Uuid = "0000000000000000000000000000beef"'
# The probe must also be readable through libsecret on the private bus: `rosecd --socket` runs
# its own broker, and the Phase 4 check depends on that path working.
DBUS_SESSION_BUS_ADDRESS="unix:path=$MIG/bus" secret-tool lookup Uuid 0000000000000000000000000000beef | wc -c
rosec item delete -y Uuid=0000000000000000000000000000beef
rosec item export Uuid=0000000000000000000000000000beef && echo "PROBE LEAKED" || echo "probe removed"
```

Checkpoint: the probe imports, exports with top-level `[attributes]`, is readable through
`secret-tool` on the private bus, deletes, and the export then fails. The probe is imported and
exported under the **same** attribute (`Uuid`), so the delete cannot miss it.

### Phase 4 — migrate and verify

```sh
python3 hack/keepassxc-to-rosec.py \
    --from "$LIVE_BUS" --to "unix:path=$MIG/bus" \
    --migrate --provider sops --report "$STAGE/migrate.json"
```

The tool pins `ROSEC_SOCKET` (and `DBUS_SESSION_BUS_ADDRESS`) from `--to` for every write, so a stray
inherited `ROSEC_SOCKET` cannot retarget it, and it refuses `--from` equal to `--to`. It imports 46
items, then re-reads them from the private daemon through `secret-tool` and `Item.Attributes`,
comparing label, attributes and secret bytes. With 46 items the cost is trivial (46 imports + 46
lookups); the provider's 512-document cache and its wholesale clear only matters at hundreds of items.

Sample through the client interface:

```sh
DBUS_SESSION_BUS_ADDRESS="unix:path=$MIG/bus" secret-tool lookup Uuid <uuid> | wc -c
DBUS_SESSION_BUS_ADDRESS="unix:path=$MIG/bus" secret-tool search --all Uuid <uuid>
```

Checkpoint: `check: 46 items match the source`; the report shows 46 `matched`, 0 `mismatch`, 0
`missing`; the store now holds 46 items plus `_meta` (`extra` lists anything else the destination
held and does not fail the run).

**Then stop the private daemon and restore the live environment** — two `rosecd` instances would
write the same sops files, and every later `busctl`/`secret-tool`/`rosec` check must answer from the
real session bus:

```sh
kill "$MIG_PID"; wait "$MIG_PID" 2>/dev/null || true
unset ROSEC_SOCKET
export DBUS_SESSION_BUS_ADDRESS="$LIVE_BUS"
rm -rf "$MIG"
busctl --user status org.freedesktop.secrets | head -3   # KeePassXC again
```

The report is written atomically, and only a `--dry-run` writes the early summary; an aborted
`--migrate` leaves no report that reads like a finished run.

### Phase 5 — cutover to one bus owner

**Pre-change (Nix), one commit:**

1. **Keep `KEEPASS_PATH` when the service is off.** `modules/universal/programs/keepassxc/default.nix`
   sets `kdn.env.variables = envs;` inside `(lib.mkIf cfg.service.enable …)` (lines 44-45). Move that
   line into the `(lib.mkIf cfg.enable …)` branch (lines 29-42); otherwise `service.enable = false`
   unsets `KEEPASS_PATH` and the `kdn-drag0nius.kdbx` wrapper fails with
   `database not found in ''`.
2. **Disable the module's `rosecd` unit without losing the provider config.**
   `modules/universal/services/rosec/default.nix` guards both the sops provider config and the
   `rosecd.service` unit with `cfg.enable`. Add a separate option
   `kdn.services.rosec.rosecd.enable` (bool, default `config.kdn.services.rosec.enable`) and move the
   `(lib.mkIf cfg.enable { systemd.user.services.rosecd = … })` block (lines 464-495) onto it. Export
   `servicePath` as a read-only option **and add `"servicePath"` to the `removeAttrs` list at
   `:399-403`**, next to `conflictScript` (the only read-only option today): a `mkDefault` on a
   read-only option aborts the
   HM forward.
3. **Make the shim run the daemon.** The shim is a **NixOS** unit (`modules/universal/desktop/sway/
   default.nix` is guarded by `ifTypes [ "nixos" ]`, and `systemd.user.services` there is nixpkgs'
   `systemd-unit-options`, which has no `Unit`/`Service` attributes). In `hosts/oams/default.nix`,
   next to the rosec block:

   ```nix
   systemd.user.services."${config.kdn.desktop.sway.systemd.secrets-service.name}" = {
     # The unit keeps `Type=dbus`/`BusName`; only the process changes. nixpkgs' `script` writes a
     # plain `serviceConfig.ExecStart`, so `mkForce` wins without a dual definition.
     serviceConfig.ExecStart = lib.mkForce "${lib.getExe' config.kdn.services.rosec.package "rosecd"}";
     serviceConfig.Restart = "on-failure";
     serviceConfig.RestartSec = 2;
     serviceConfig.Environment = [
       "PATH=${config.kdn.services.rosec.servicePath}"
       "SOPS_AGE_KEY_FILE=${config.kdn.services.rosec.providers.sops.key_file}"
     ];
     wants = [ "rosec-keys.service" ];
     after = [ "rosec-keys.service" ];
   };
   ```

   `kdn.services.rosec.enable = true; kdn.services.rosec.rosecd.enable = false;` — the shim is the
   only `Type=dbus`/`BusName` owner, so `systemd-analyze --user verify` accepts the transaction.
   Verify with `systemctl --user cat dbus-kdn-sway-secrets-service.service`: exactly one `ExecStart=`,
   and it names `rosecd`.
4. **Disable the KeePassXC service without an orphan.** The unit lives inside
   `(lib.mkIf cfg.service.enable …)`, but `modules/universal/profile/user/kdn/default.nix:479-493`
   adds `Unit` + `Install.WantedBy` outside it. Wrap those lines in
   `lib.mkIf config.kdn.programs.keepassxc.service.enable`; an empty `mkForce []` leaves a unit with
   no `ExecStart` and systemd refuses it.
5. **Turn FdoSecrets off for good.** In `keepassxc.ini` set `[FdoSecrets] Enabled=false`, and in
   `packages/kdn-keepass/kdn-keepass.sh` add `: "${FDO_ENABLED:="false"}"` and use `"$FDO_ENABLED"`
   in the `upsert_fdo_key Enabled` call. The plugin writes the ini key only from its settings widget,
   so the value survives a `keepassxc %f` start; confirm after one GUI start.

**Cutover** (stop the incumbent **before** the switch, then restart the shim explicitly — HM
`startServices = "suggest"` restarts nothing):

```sh
systemctl --user stop keepassxc.service
sudo nixos-rebuild switch --flake "git+file://$PWD#oams"
systemctl --user daemon-reload          # belt: 26.11 reloads user managers itself
systemctl --user restart dbus-kdn-sway-secrets-service.service
systemctl --user cat rosecd 2>&1 | head -1                           # must be "No files found" (rosecd.enable = false)
busctl --user status org.freedesktop.secrets | head -3         # the rosecd PID
systemctl --user is-active dbus-kdn-sway-secrets-service.service
systemctl --user status nextcloud-client.service
rosec status                                                     # runtime identity reused from phase 2?
```

`switch-to-configuration-ng` (the only switch implementation in 26.11) reexecutes and reloads every
user manager, so the unit file is normally current before the restart. Keep the explicit
`daemon-reload` as a belt, and keep the restart because `systemd.user.startServices = "suggest"`
starts or restarts nothing by itself.

Client checks:

```sh
secret-tool lookup Uuid <uuid>
secret-tool search --all Uuid <uuid>
secret-tool search --all application chrome        # a real client search, works today (rc 0)
git credential-libsecret get <<<'protocol=https
host=github.com
'
```

Checkpoint: `busctl` names the `rosecd`, not KeePassXC; the shim is active; `nextcloud-client` is
active; the sample items return the same secrets; a GUI start leaves the bus with the `rosecd`; the
KDBX hash is unchanged.

### Phase 6 — observe (1 week)

- `rosec-sops conflicts list`: empty; the `rosec-conflicts` timer/path state stays empty.
- The real clients: Element, Chrome/Chromium, Bitwarden, IntelliJ, gh, poetry, Nextcloud, Remmina.
- KeePassXC GUI, browser integration and SSH agent still work; FdoSecrets stays off.
- The store: 46 item files plus `_meta`; no plaintext.

### Phase 7 — retire / rollback

Retire: keep the KDBX and the disabled `keepassxc.service`; keep the phase-0 hash; delete `$STAGE`
after the observation; update `docs/rosec.md` and this task's `done.md`.

Rollback (any time before the KDBX is deleted):

```sh
# Nix: `kdn.services.rosec.enable = false` (and `rosecd.enable` follows), the shim override removed,
#      the profile guard restored, `kdn.programs.keepassxc.service.enable = true`,
#      `FDO_ENABLED=true`, `keepassxc.ini [FdoSecrets] Enabled=true`
sudo nixos-rebuild switch --flake "git+file://$PWD#oams"
systemctl --user restart dbus-kdn-sway-secrets-service.service      # back to `sleep infinity`
systemctl --user start keepassxc.service
busctl --user status org.freedesktop.secrets                        # KeePassXC owns the name again
```

The shim stays active (its process is `sleep`), so `nextcloud-client` never loses its `Requires`. The
rosec store stays; a re-run of the migration deletes by `Uuid` and re-imports.

## 5. Why the shim, not a second daemon

The shim is the D-Bus **name holder**: `Type=dbus`, `BusName=org.freedesktop.secrets`,
`ExecStart=sleep infinity`, `nextcloud-client` `Requires` it, and KeePassXC is `WantedBy` it. Two
`Type=dbus` units cannot allocate one name, so the cutover keeps the single unit, points its
`ExecStart` at the `rosecd`, and disables the module's own `rosecd.service`. The unit name, the
`dbus-1` service file, the `nextcloud-client` dependency and the 120 s cold-start bound all stay
unchanged.

## 6. Attack log

| # | Finding | Fix |
| --- | --- | --- |
| scope | the KDBX holds 1031 entries, but only **46** are Secret Service items | migrate the 46; drop the whole-database mapping, the XML export and `keepassxc-cli` |
| scope | `keepassxc-cli export` drops attachment secrets (`Meta/Binaries` empty) | the live bus is the source; 1 of 46 is an attachment |
| scope | item object paths change under load | address by the `Uuid` attribute; retry attributes |
| 1st B1 | shim + module `rosecd` both `Type=dbus`/`BusName` | one owner: the shim runs the `rosecd`; `rosecd.enable = false` |
| 1st B2 | GUI `keepassxc %f` bypasses the wrapper and re-enables FdoSecrets | ini `Enabled=false` + `FDO_ENABLED`; verify after a GUI start |
| 1st B5 | "492 sensitive fields would become public" | moot at 46; attributes are copied verbatim and are already public on D-Bus |
| 1st/2nd B6 | `service.enable=false` leaves an orphan unit | guard the profile `Unit` + `Install.WantedBy` (`:479-493`) |
| 1st M1 | `--force` is not an upsert | delete by `Uuid`, then import |
| 2nd B1 | `keepassxc-cli export` has no `--pw-stdin`; `--quiet` sends the prompt to `/dev/null` | no CLI export at all |
| 2nd B4 | the check needs a live daemon | the private daemon stays up through the check |
| 2nd B5 | the switch restarts the shim while KeePassXC holds the name | stop KeePassXC first |
| 3rd B1 | `item import` never unlocks the private daemon | `rosec unlock` before the probe |
| 3rd B2 | `keepassxc:uuid` is an illegal bare TOML key | quote every key; `--dry-run` re-parses all TOML |
| 3rd B3 | the switch restarts nothing (`suggest`), the shim is inactive | explicit `systemctl --user restart` |
| 3rd B4 | the profile `Unit` block stays unguarded | wrap `:479-493` |
| 4th B1 | `systemctl --user status` on an inactive oneshot aborts under `set -e` | `set -uo pipefail`; `is-active … || true` |
| 4th B2 | `rosec unlock --gui` under a fake `XDG_RUNTIME_DIR` panics (`NoCompositor`) | keep the real runtime dir; `script -qec` pty, `--gui` fallback |
| 4th B3 | the probe exported a different attribute than it imported | probe import/export/delete all use `Uuid` |
| 4th B4 | `/tmp/rosec-mig` is world-readable | `mktemp -d` (0700) |
| 4th M | O(N²) apply/check | 46 items: 46 imports and 46 lookups |
| 4th M | `rosec item export` hides `rosec:`/`xdg:` attributes | verify through `Item.Attributes`, not the export |
| 4th M | `service.enable=false` drops `KEEPASS_PATH` | move `kdn.env.variables` out of the service guard |
| 4th M | the package's activation file still names `rosecd.service` | with `rosecd.enable=false` it must not install; check `systemctl --user cat rosecd` |
| 4th M | two unwraps | sharing `XDG_RUNTIME_DIR` reuses one runtime identity; `rosec status` confirms the daemon |
| 5th B1 | `rosec` resolves `ROSEC_SOCKET` before the session bus; only a `_MIG` variable was exported, so the unlock and the probe hit KeePassXC | capture `LIVE_BUS`, then export `ROSEC_SOCKET` **and** `DBUS_SESSION_BUS_ADDRESS`; the tool pins both from `--to` |
| 5th B2 | the shim is a NixOS unit; `Unit`/`Service` are HM-only attributes | `serviceConfig.ExecStart = lib.mkForce …` (nixpkgs `script` writes a plain definition) |
| 5th M1 | a read-only `servicePath` aborts the HM forward | add `"servicePath"` to the module's `removeAttrs` |
| 5th M2 | no source≠dest guard; an inherited `ROSEC_SOCKET` outranks `--to` | the tool refuses equal buses and pins `ROSEC_SOCKET` |
| 5th M3 | `org.gnome.keyring.NetworkPassword` occurs 0 times | use `secret-tool search --all application chrome` (rc 0 today) |
| 5th M4 | rosec drops empty attribute values, so "verbatim" is not exact | stated in the mapping; the check compares non-empty values only |
| 5th M5 | `rosec provider list` cannot prove the private daemon is unlocked | `rosec status` + the probe import |
| 6th | the private daemon and its env vars survived into the cutover: two writers, and every bus check answered from the private bus | stop it, `unset ROSEC_SOCKET`, restore `DBUS_SESSION_BUS_ADDRESS`, `rm -rf "$MIG"` |
| 6th | no `systemctl --user daemon-reload` after the switch | reload before the restart, kept as a belt: 26.11 reloads user managers itself |
| 6th | an aborted `--migrate` left a summarize-only report that read like a finished run | atomic write; the early summary is written for `--dry-run` only |
| 6th | a TOML parse error can quote a secret, and the mutate path never validated | `validate()` before the first write; the report carries exit codes only |
| 6th | the probe `grep '^\[attributes\]'` was vacuous | assert the exported `Uuid` value |
| 6th | the check was one-directional | report the destination's `extra` items without failing |
| 7th M1 | `toml_key` leaves `Uuid` bare, so the probe grep could never match | pattern is `^Uuid = "…"` |
| 7th M2 | the destination check overwrote `error: import failed` with `matched`, so `--migrate` exited 0 | error statuses are never overwritten; the apply error list decides the exit code |
| 7th M3 | the plan claimed the switch does not reload user units | 26.11's `switch-to-configuration-ng` reexecutes and reloads them; the claim is corrected |
| 7th M4 | no proof that libsecret works over the private `busd` broker | Phase 3 reads the probe with `secret-tool` on the private bus |

## 7. Acceptance

- The dry run reports 46 items; the migrate report shows 46 `matched`, 0 mismatch, 0 missing.
- `secret-tool` on the live bus returns the same bytes for every sampled item, and a real client
  search (`secret-tool search --all application chrome`) still finds its item after the cutover.
- Exactly one unit owns `org.freedesktop.secrets` and its `ExecStart` is `rosecd`;
  `systemd-analyze --user verify` is clean.
- `nextcloud-client` is active; `keepassxc.service` is inactive; the KDBX hash is unchanged.
- A KeePassXC GUI start leaves the bus with the `rosecd` (FdoSecrets stays off).
- The store is `derived`, holds 46 items plus `_meta`, and the conflict list is empty.

## 8. References

- [definition.md](definition.md), [docs/rosec.md](../../../rosec.md).
- `hack/keepassxc-to-rosec.py` (the tool).
- `packages/kdn-keepass/kdn-keepass.sh`; `modules/universal/programs/keepassxc/default.nix`;
  `modules/universal/desktop/sway/default.nix` (`secrets-service`);
  `modules/universal/services/rosec/default.nix` (`rosecd`); `modules/universal/profile/user/kdn/default.nix:479-493`.
- The rosec fork (`~/dev/github.com/nazarewk-iac/rosec`): `rosec-secret-service/src/item.rs`
  (`GetSecret`), `rosec-core/src/lib.rs` (`selected_secret_value`, `RESERVED_ATTRIBUTES`),
  `rosec/src/item/mod.rs` (`parse_item_toml`, `build_item_toml`).
- Earlier reviews: `poc/review-migration-plan.md` … `-4.md` (they analysed the 1031-entry scope;
  the scope, not their unit/cutover findings, is what changed).
