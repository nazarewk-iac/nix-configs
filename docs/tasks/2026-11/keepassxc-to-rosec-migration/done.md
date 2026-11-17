---
type: Solution
description: The 46 live Secret Service items moved from KeePassXC into the rosec derived sops store on oams, and one name-holder unit now runs the rosecd.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T19:13:13+01:00
---

# Solution

## Scope

The Secret Service exposed **46 items**, not the whole KDBX:

| Fact | Value |
| --- | --- |
| Live items | 46, all in the group `drag0nius/secret-service`, 46/46 matched by UUID |
| KDBX | 1031 current entries; the other 985 are the personal vault and were never exposed |
| Secrets | 45 equal the entry `Password`; 1 is an attachment (`FDO_SECRETS_DATA`) that `keepassxc-cli export` drops |

The bus, not the export, was therefore the source. The vault stays in KeePassXC; deleting the
`secret-service` group later is a manual, one-folder step.

## Procedure

`hack/keepassxc-to-rosec.py` copies bus to bus:

1. read the live daemon (`Item.Attributes` via `busctl --json`, secrets via
   `secret-tool lookup Uuid=<uuid>`);
2. emit `[item]` + top-level `[attributes]`/`[secrets]` TOML, every key quoted, `type = "login"` so
   `GetSecret` returns `password`, binary secrets as `{ base64 = "…" }`;
3. write through a **private** `rosecd --socket` in a `0700` `mktemp` directory, with `ROSEC_SOCKET`
   pinned per call, after deleting the previous copy by `Uuid` (`item import --force` is not an
   upsert);
4. verify from the destination through the same client interface, then stop the private daemon and
   restore `DBUS_SESSION_BUS_ADDRESS`.

The route was rehearsed before any write: a probe item proved the TOML shape, the bare `Uuid` key in
the export, and libsecret over the private `busd` broker (`secret-tool lookup` returned 5 bytes).

## Result

| Check | Result |
| --- | --- |
| Imported | 46 items, 0 errors |
| Destination check | 46 matched, 0 missing, 0 mismatch, 0 extra |
| Store | 47 files: 46 `item-*.sops.yaml` + `_meta.sops.yaml`, all `ENC[AES256_GCM,…]` |
| Live bus after cutover | `busctl --user status org.freedesktop.secrets` names the `rosecd` |
| Client reads | 46/46 `secret-tool lookup Uuid=<uuid>`; `secret-tool search --all application chrome` returns the item with `schema = chrome_libsecret_os_crypt_password_v2` |
| `nextcloud-client` | active (its `Requires` on the name holder is unchanged) |
| KDBX | unchanged (`ac3cfdd7…3196`), entries still present |
| Conflicts | none |

## Cutover

One switch:

- `kdn.services.rosec.enable = true`, `kdn.services.rosec.rosecd.enable = false` — a new module
  option guards the module's own `rosecd.service`, so only one `Type=dbus` unit allocates
  `org.freedesktop.secrets`;
- `hosts/oams`: the `kdn-secret-service` name holder gets
  `serviceConfig.ExecStart = lib.mkForce <rosecd>` (nixpkgs' `script` writes a plain `ExecStart`),
  the provider `PATH`/`SOPS_AGE_KEY_FILE`, and `wants`/`after` `rosec-keys.service`;
- `kdn.programs.keepassxc.service.enable = false`, forced inside the Home Manager evaluation because
  the module forwards the option with `mkDefault`; the profile guard wraps the whole unit, not just
  `WantedBy`, so no unit without `ExecStart` is left behind;
- `kdn.env.variables` (`KEEPASS_PATH`) moved out of `service.enable`, so the `kdn-keepass` wrapper
  still finds the KDBX;
- `[FdoSecrets] Enabled=false` in `keepassxc.ini`, `FDO_ENABLED=false` in `kdn-keepass.sh`.

The unlock is one YubiKey operation per session (slot 3, no PIN, no touch): the first client, or
`rosec unlock`, unwraps the master into `/run/user/<uid>/rosec/store-identity.age`.

## Rollback

Keep the KDBX. Set `kdn.services.rosec.enable = false`, remove the host shim override, restore the
profile guard, set `kdn.programs.keepassxc.service.enable = true` and `FDO_ENABLED=true`, set the ini
`Enabled=true`, switch, restart the name holder, start `keepassxc.service`. The rosec store stays; a
re-run of the tool deletes by `Uuid` and re-imports.

## Follow-up: the bus-name and ordering traps

Three problems appeared after the first cutover, and each has a lasting fix:

- **A second bus owner.** The rosec *package* ships `rosecd.service`/`rosecd.socket` and a
  session-bus activation file in the user profile, so systemd finds them through `XDG_DATA_DIRS`
  independently of Home Manager. Masking the unit left the activation file pointing at a dead unit.
  `rosecd.service` is now an **alias** of the name holder, so activation starts the shim and exactly
  one unit owns the bus.
- **A locked store at login.** `rosec` has no silent unlock path, so a client that starts before the
  first unlock cannot read its item. `rosec-unlock.service` (oneshot, `After` the shim, `Before`
  `nextcloud-client`, `WantedBy graphical-session.target`) unlocks once with the YubiKey.
- **Duplicate items on every Nextcloud start.** rosec replaces an item only when the secret is
  equal; the client writes `secret` while the migrated item used `password`, so the create never
  matched and added a new item. The two Nextcloud items are now client-owned (`type = "generic"`,
  `[secrets] secret`), and two restarts added nothing.

Final shape: 46 items — 44 still carry the source `Uuid`, the two Nextcloud items are owned by the
client and read by `server`/`user`/`type`.
