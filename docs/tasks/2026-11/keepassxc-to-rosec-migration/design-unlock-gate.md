---
type: Design
description: An unlock gate for the rosec Secret Service — v2 after three attacks. The daemon fix is primary; the gate is a Nextcloud-shaped band-aid with exact unit semantics.
task: definition.md
authored_by: agent
timestamp: 2026-11-23T12:00:00+01:00
---

# Unlock gate — design v2 (after three attacks)

Attacks: `poc/attack-unlock-gate-systemd.md`, `-ux.md`, `-rosec.md`.

**Verdict of the round:** v1 was not shippable. All three reviews agree the 4.6 s window is a
**daemon ordering bug**, and that a gate built on secret probes cannot be correct. Two layers:

1. **Primary — fix the daemon.** Small, covers every client (including bus activation), deletes most
   of the gate.
2. **Secondary — a thin gate** for clients that start before the daemon is ready, with the mechanics
   the attacks demand. It **replaces** `rosec-unlock.service`; it does not sit beside it.

## 1. Primary: the daemon fix

| # | Change | Where | Why |
| --- | --- | --- | --- |
| D1 | mark the provider unlocked **after** the cache is rebuilt | `rosec-secret-service/src/state.rs:1450`, `mark_provider_unlocked` after `rebuild_cache_inner` | `unlocked` currently precedes the sync by ~4.6 s; this is the window that breaks Nextcloud |
| D2 | auto-unlock providers with `required: false` at startup | `rosecd/src/main.rs`, after the config is loaded and **before** `request_name` (bounded, best-effort) | sops needs no credential (`provider.rs:490`); only the empty-password pipe check blocks it (`management.rs:652`) |
| D3 | bound D2 (e.g. 15 s) and continue locked on failure | same | a missing YubiKey must not block the bus name |
| D4 | re-unlock after resume | `rosecd/src/main.rs:960-975` (`PrepareForSleep`) | `lock()` deletes the runtime identity (`provider.rs:683`), so one sleep locks the store for the session |
| D5 | per-store runtime identity | `rosec-core/src/config.rs:248` | two sops stores share one file; the second can never unlock |
| D6 | `rosec unlock --no-prompt` (or accept the pipe path) | `rosec-secret-service/src/management.rs:652` | removes `expect` from every unit |

D1+D2 make `Type=dbus` readiness mean "serves items", so **no client needs a gate**. D2 must run
**after** the config load and **before** the name claim; it must never run inside `rebuild_cache`,
where the 30 s YubiKey timeout would delay the bus name.

## 2. Secondary: the gate

Keep it only for the case the daemon cannot cover: a client that starts while the daemon is still
locked (key absent, or a restart). It **replaces** `rosec-unlock.service`.

### Units (per provider, `%i` = rosec provider id)

```ini
# secret-service-unlock@.service — the only unlock path
[Unit]
Description=Unlock and verify rosec provider %i
Requires=kdn-secret-service.service
After=kdn-secret-service.service
PartOf=kdn-secret-service.service
[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=45s
ExecStart=/nix/store/.../rosec-unlock-gate %i
```

```ini
# secret-service-unlocked@.target — the gate
[Unit]
Description=rosec provider %i is unlocked and serving
Wants=secret-service-unlock@%i.service
After=secret-service-unlock@%i.service
BindsTo=secret-service-unlock@%i.service
PartOf=secret-service-unlock@%i.service
```

Dependents: `Wants=` + `After=` the target, **never** `Requires`/`BindsTo`, so they keep running
when it dies. The gate's `TimeoutStartSec` bounds their wait; on failure they start anyway, degraded.

### The gate script (no secrets, no prompts, no activity)

```sh
# 1. create the sentinel when absent — AFTER the unlock, with a label and one dummy secret
rosec unlock            # or the pipe path once D6 lands
# 2. wait until the daemon reports a served cache
for _ in $(seq 1 120); do
  n=$(busctl --user call org.freedesktop.secrets /org/rosec/Daemon \
        org.rosec.Daemon Status 2>/dev/null | awk '{print $2}')
  [ "${n:-0}" -gt 0 ] && exit 0
  sleep 0.25
done
exit 1
```

- `Status()` is the verified signal: `busctl … Status` returned `u 46` live. It is not
  `rosec status`'s `STATE` (which lies until D1 lands), and it does not touch secrets.
- **Never** `secret-tool`/`GetSecret`/`SearchItems` on the periodic path: they call
  `Service.Unlock` (`service.rs:250`), spawn `rosec-prompt` **in the daemon's cgroup** (so
  `timeout` cannot kill it), and call `touch_activity` (`service.rs:113,133`), which defeats
  idle auto-lock.
- Absolute paths only: NixOS user units get `PATH=coreutils:findutils:gnugrep:gnused:systemd`.

### Detection (not retry)

```ini
# secret-service-probe@.timer
[Timer]
OnBootSec=30s
OnUnitInactiveSec=20s
AccuracySec=1s
```

`secret-service-probe@.service` reads `Status()`; when it drops to 0 it **stops the unlock
service**, which kills the target, and notifies once. It never unlocks on its own, so `rosec lock`
stays a real lock. The timer is the safety net for the `Restart=on-failure` window, where `BindsTo`
does not fire while the daemon sits in `activating (auto-restart)`.

### Cues

- **Graphical**: `notify-send -u normal -t 0 -p -r 4100 "rosec: <provider> locked" "…YubiKey…"`;
  reuse the id with `-r` to update, and dismiss it when the gate becomes ready. Never
  `-u critical` with the default timeout (swaync's `timeout-critical: 0` means it never expires).
- **Non-graphical**: `logger -t rosec-gate`, the failed unit state, and
  `~/.local/state/rosec/gate/<provider>.state` with `state=ready|locked|absent` and a `reason`.
  The state file is the machine-readable cue a waybar module or a `rosec-gate-status` command can
  read.

## 3. What the gate cannot do

- It does **not** reach clients that **bus-activate** `rosecd` (Chromium, Element, IntelliJ, `gh`,
  poetry). Only D1+D2 cover them.
- It does not survive a daemon restart mid-session unless the probe timer notices within one tick.
- It does not make a locked store usable; it only makes the gate honest.

## 4. Findings that changed the design

| Attack | Finding | v2 |
| --- | --- | --- |
| systemd | `BindsTo` misses the auto-restart window | timer is the safety net; probe every 20 s |
| systemd | unit `PATH` has no `secret-tool` | `busctl` with absolute path |
| systemd | probe spawns a prompt in the daemon cgroup | `Status()`, never `secret-tool` |
| systemd | `STATE=unlocked` precedes the sync | D1 |
| systemd | `OnUnitActiveSec` invalid for a oneshot | `OnUnitInactiveSec` |
| systemd | `Wants`+`After` can hang the dependent | gate `TimeoutStartSec=45s` |
| UX | `rosec unlock` needs a TTY and unlocks all providers | D6 + per-provider unlock; the gate script is the only unlocker |
| UX | a rival unlocker beside `rosec-unlock.service` | the gate **replaces** it |
| UX | bus-activation clients bypass ordering | stated limitation; D2 is the fix |
| UX | critical notification never expires | `-u normal -t 0 -p -r` + dismissal |
| UX | stateless probe cannot notify on transition | the state file carries the previous state |
| UX | `start …target` is a no-op on recovery | recovery is `restart secret-service-unlock@…service` |
| rosec | sentinel creation fails before unlock / needs a label+secret | create after the unlock, with a label and one dummy secret |
| rosec | `kdn-sentinel` survives | keep the attribute; it is neither internal nor reserved |
| rosec | `Items` does not change on lock | `Status()` + per-item `Locked` subscription if a push signal is needed |
| rosec | probe defeats auto-lock | no `SearchItems`/`GetSecrets` on the periodic path |
| rosec | no resume branch | D4 |
| rosec | two stores share the runtime identity | D5 |

## 5. Open decisions for the user

1. **Ship the daemon fix first and drop the gate?** D1+D2+D4 make the gate unnecessary for every
   client. The gate only earns its place for the "key absent at login" cue and the retry-on-use.
2. **Auto-unlock at startup**: with the key present, the bus name waits ~1–10 s; with the key
   absent, it waits the D3 bound. Acceptable at boot?
3. **Sentinel item**: a dummy item per provider in the store (one extra sops file) versus probing
   `Status()` alone. With D1, `Status()` is truthful and the sentinel may be unnecessary.
4. **Instance key**: provider id (`sops`) or store path hash (needed once D5 lands and a host runs
   two stores).
5. **Notification policy**: one card per provider, updated in place, or a single aggregate card?

## 6. Implementation status (2026-11-23)

The gate is implemented **opt-in**: `kdn.services.rosec.unlockGate.enable` (default `false`), so
`oams` keeps `rosec-unlock.service` until the gate is accepted. The units are emitted from the
rosec module (scope `user` by default, `system` for the test), with `PATH` set to the provider
`PATH` — `expect` spawns `rosec`, and a missing `PATH` was the first bug the test caught.

`tests/rosec-gate/` is a NixOS test with a stub daemon, a stub `rosec` and a stub `busctl`. It
proves the three promises:

1. a dependent start pulls the target, which pulls the unlock, and the dependent then runs;
2. a lock (served items drop to 0) makes the probe stop the gate — the target dies, the dependent
   survives;
3. restarting the dependent re-arms the gate.

It also caught the state-file bug: the file was named after the subcommand (`wait.state`) instead
of the provider (`sops.state`). The script now keys it by provider.

Run it with:

```sh
nix build --impure --expr 'let f = builtins.getFlake "git+file://$PWD";
  p = import f.inputs.nixpkgs { system = "x86_64-linux"; };
  in p.callPackage ./tests/rosec-gate { }'
```

The test uses `scope = "system"`; the user-scope wiring (the `--user` flags and the session bus)
is the only part it does not exercise, and it is a two-flag difference in the script.
