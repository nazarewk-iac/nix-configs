---
type: Review
description: Consolidated design review of the rosec secret-service modules (universal, den, runtime), with severity, file:line and the suggested change. Nothing here is applied.
task: definition.md
authored_by: agent
timestamp: 2026-11-17T10:30:00+01:00
---

# Module design review — rosec secret service

Three independent read-only reviews ran on 2026-11-17:

| Review                       | File                                    |
| ---------------------------- | --------------------------------------- |
| Universal (NixOS/HM) modules | `poc/review-module-design-universal.md` |
| Den aspects                  | `poc/review-module-design-den.md`       |
| Runtime semantics            | `poc/review-runtime-semantics.md`       |

**Verdicts:** `oams` works as it runs today (46 items, unlocked, no conflicts). The den aspect is
**not safe to enable**. Six universal majors and one runtime high are worth fixing before the next
host adopts this.

## 1. Do not enable the den aspect yet

| #   | Severity    | Finding                                                                                                                                                  | Change                                                                                                                                         |
| --- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| D1  | **blocker** | `systemd.user.units` does not exist in Home Manager (`service-rosec.nix:513`); eval fails as soon as `use = true`                                        | mask in the HM context differently (a `~/.config/systemd/user/rosecd.socket -> /dev/null` link via `home.file`, or drop the socket mask there) |
| D2  | high        | `WantedBy` written inside `[Unit]` (`:521`); HM only honours `Install.WantedBy`, so `rosec-unlock` is never pulled                                       | move to `Install.WantedBy`; add a den equivalent of the nextcloud `Wants`                                                                      |
| D3  | high        | `Aliases` in `[Unit]` is the wrong section and key (`Alias=` belongs in `[Install]`), and HM never runs `systemctl enable`                               | drop the alias from HM; let the host or a `home.activation` create it, or document that the alias is NixOS-only                                |
| D4  | high        | the HM unit shadows the NixOS name holder in `~/.config/systemd/user`, losing envs ordering, `Slice`, 120 s timeout (`:539-566`, `desktop-sway:943-974`) | emit the unit from the NixOS evaluation like the universal module, or make the HM unit carry the holder's ordering                             |
| D5  | medium      | missing the 0600 config activation (`universal:534-545`)                                                                                                 | port the `home.activation`                                                                                                                     |
| D6  | medium      | config not rendered for `keyGeneration` alone (`:474`)                                                                                                   | add the third term to the gate                                                                                                                 |
| D7  | low         | read-only `servicePath` has no consumer and no forward (dead API)                                                                                        | drop it or wire the consumer                                                                                                                   |
| D8  | low         | the "no reachable `enable`" rule is contradicted by `rosecd.enable`/`unlock.enable`/`keyGeneration.enable`                                               | document that the rule is about the top-level switch                                                                                           |
| D9  | low         | `providers.sops.path` gained `default = ""` (fail-fast lost), `defaultText`/`example` dropped, duplicated comment                                        | restore the universal shape                                                                                                                    |

## 2. Universal module — majors

| #   | Severity | Finding                                                                                                                                   | Change                                                                                                                      |
| --- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| U1  | major    | `expect` never checks the outcome (`rosec/default.nix:108-117`), so a missing YubiKey yields a **successful** oneshot over a locked store | assert on the "unlocked" line and exit non-zero, or use a non-interactive `rosec unlock --no-prompt` (see R4)               |
| U2  | major    | the re-declared unit drops the package's `LimitMEMLOCK=infinity` and `RUST_LOG` (`:85-97`, confirmed in the generated unit)               | copy both into the unit, or extend the package's unit instead of re-declaring it                                            |
| U3  | major    | no `PartOf` on the daemon (`:100-104`), so a crash/restart never re-unlocks                                                               | add `PartOf` (or `BindsTo`) the unlock unit and `After` it, or re-run the unlock from `ExecStartPost` with a working `PATH` |
| U4  | major    | `nextcloud-client.Unit` is unguarded (`profile/user/kdn:496-513`); a sway host without nextcloud gets an `ExecStart`-less unit            | guard with `config.services.nextcloud-client.enable` or the module's own switch                                             |
| U5  | major    | `ifTypes [ "nixos" ]` leaves a standalone Home Manager with no unit (`:495`)                                                              | add a `hasParentOfAnyType` fallback that emits the unit in HM when there is no NixOS parent                                 |
| U6  | major    | D-Bus activation lives in the sway module (`desktop/sway:498-517`), so an adopter gets no activatable `org.freedesktop.secrets`           | move the `dbus-1` service file into the rosec module, keyed by `rosecd.unitName`                                            |

## 3. Runtime semantics

| #   | Severity | Finding                                                                                                                                                                | Change                                                                                                                      |
| --- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| R1  | **high** | `PrepareForSleep` always locks (`rosec/src/main.rs:989`) and nothing re-unlocks; autolock is off today, but enabling it strands headless clients                       | install the PAM hook, or a `swayidle` resume hook that runs the unlock unit; decide the policy before enabling `[autolock]` |
| R2  | medium   | the unlock prompt has no timeout (that is the measured `secret-tool` hang)                                                                                             | upstream: bound the prompt; config: nothing                                                                                 |
| R3  | medium   | duplicate-on-rotation is deliberate and tested (`rosec-sops/src/provider.rs:851`, `tests.rs:308-317`); wrong for `replace=true`                                        | decide the policy; a fork patch that replaces on attribute match would fix it                                               |
| R4  | medium   | `AuthProviderFromPipe` already exists; one empty-password check blocks it (`rosec-secret-service/src/management.rs:651`)                                               | add `rosec unlock --no-prompt`; then drop `expect` (U1) and the pty entirely                                                |
| R5  | low      | config watcher is content-gated (`main.rs:1677`), so the 0600 copy is harmless; 0600 only silences a warning (`main.rs:2178`); a provider-block edit silently re-locks | document                                                                                                                    |
| R6  | low      | `ssh_fuse = false` also disables rosec's `agent.sock`; the option description understates it                                                                           | fix the description                                                                                                         |
| R7  | info     | no conflict archives from normal use; they need a Syncthing conflict copy                                                                                              | none                                                                                                                        |

## 4. Suggested order

1. **D1** — the den aspect cannot evaluate; fix or keep it unwired.
2. **R4 + U1** — `rosec unlock --no-prompt` removes `expect`, the pty and the false success in one move.
3. **U2, U3** — the unit must keep the package's hardening and must re-unlock after a restart.
4. **U4, U5** — the guard and the HM fallback; both are small and prevent a broken unit on the next host.
5. **U6** — move the D-Bus activation file next to the unit it names.
6. **R1** — decide the lock policy before any host enables autolock.
7. D2-D9, U6's leftovers, R2/R3/R5-R7 — polish and fork work.

## 5. Not applied

Nothing in this document is applied. The module and host files are untouched; the other session
reworking `brys` onto den keeps a clear field. The three source reviews hold the long form.
