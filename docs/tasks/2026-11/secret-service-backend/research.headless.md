---
type: Research
description: How each Secret Service candidate behaves with no desktop environment — start paths, prompt behaviour when locked, exact repro commands.
status: open
authored_by: agent
timestamp: 2026-11-14T00:45:00+01:00
---

# Headless behaviour of the candidates

Task requirement recap (from [definition.md](definition.md)): no X11, no Wayland, no
`DISPLAY`, no `WAYLAND_DISPLAY`, session bus may be the systemd user bus only; every
unlock, prompt and error path must work from a TTY or SSH; a GUI dialog that cannot be
shown counts as a **failure**, not a degradation.

Two distinct headless questions per candidate:

- **H1 — start:** can the provider register `org.freedesktop.secrets` with no display?
- **H2 — locked-state:** when a client asks for a secret and the store is locked, does
  the daemon (a) answer through a non-GUI channel (TTY prompt, askpass-style program,
  helper socket), (b) fail cleanly (IsLocked / dismissed prompt), or (c) **hang** behind
  a Qt/GTK dialog that no one will ever see? (c) is the disqualifier.

## Summary

| Candidate                                                              | H1 start, no display                                                                                                                                                                           | H2 locked state                                                                                                                                                                                                                                                                                                                                                                                                                                          | Verdict                                                                                                             |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **rosec**                                                              | ✅ `Type=dbus` unit, socket unit, embedded private-bus fallback (`$XDG_RUNTIME_DIR/rosec/bus`) when there is no session bus at all                                                             | ✅ **fail-closed ladder**: `SSH_ASKPASS` → `[prompt] backend` custom binary → TTY prompt via `rosec-prompt --tty` → hard error with a clear message. Never a blind dialog; no hang                                                                                                                                                                                                                                                                       | passes both, by design                                                                                              |
| **gopass secret-service** (1.17.4) / **gopass-secret-service** (0.3.1) | ✅ both are pure-Go daemons, no display; the standalone unit wants `default.target` (headless-correct); the built-in unit wants `graphical-session.target` (override, or use D-Bus activation) | ✅ no D-Bus prompts at all (all ops return `"/"`); unlock happens in the age backend: touch on the YubiKey, agent socket, or passphrase via TTY/stdin; if nothing is available the client **fails** (measured: D-Bus error, rc=1) but the daemon **retries pinentry in a loop** (measured: repeated `pinentry error: failed to ask for PIN: could not get state of terminal`) — with the GPG backend a pinentry would instead hang, so: age backend only | passes both (age backend required)                                                                                  |
| **oo7**                                                                | ✅ D-Bus-activated `Type=dbus` user unit, `PrivateNetwork=yes`                                                                                                                                 | ✅ daemon has no prompt UI; it delegates to a prompter type; with no portal/GUI it uses `org.freedesktop.secrets.CliPrompter`, owned by `oo7-cli`, which prompts on the TTY; a non-`oo7-cli` caller while locked gets a **dismissed prompt** (clean failure, no hang)                                                                                                                                                                                    | passes both                                                                                                         |
| **KeePassXC 2.8.0**                                                    | ⚠️ starts offscreen (`QT_QPA_PLATFORM=offscreen`, segfault fixed in 2.8.0 #13761); provider lives **inside the GUI MainWindow process** (MainWindow.cpp:228)                                   | ❌ every prompt is a Qt dialog: locked DB → `Collection.Unlock` never completes; with the default `UnlockBeforeSearch=true`, a `Search` **hangs the D-Bus dispatch thread** in a nested `QEventLoop` behind an invisible dialog. No programmatic answer path in 2.8.0 (no D-Bus reply, no file, no env)                                                                                                                                                  | fails H2 unless the store is **never locked** + the two config overrides + `Restart=always` with re-unlock on start |
| **grimsteel/pass-secret-service**                                      | ✅ never prompts; unlock = gpg-agent state; `can_prompt` fail-fast (`--pinentry-mode=error`)                                                                                                   | ✅ clean failure when the agent is locked (no pinentry)                                                                                                                                                                                                                                                                                                                                                                                                  | passes both (gpg today; age/sops via fork)                                                                          |
| **mdellweg/pass_secret_service**                                       | ⚠️ starts fine                                                                                                                                                                                 | ⚠️ prompt module disabled; pypass uses `gpg --use-agent` → pinentry possible hang when the agent is locked; ten other spec bugs (see [research.md](research.md))                                                                                                                                                                                                                                                                                         | fails the spec, not only headless                                                                                   |
| **yousefvand**                                                         | ❌ prompt path shells out to `wmctrl` (GUI dependency, archived)                                                                                                                               | ❌ batch `GetSecrets` panics on plain sessions (libsecret's multi-result path)                                                                                                                                                                                                                                                                                                                                                                           | fails                                                                                                               |
| **bitw**                                                               | n/a                                                                                                                                                                                            | n/a                                                                                                                                                                                                                                                                                                                                                                                                                                                      | rejected earlier (online binding)                                                                                   |
| **gnome-keyring / ksecretd**                                           | reference only                                                                                                                                                                                 | GUI prompt (GTK/Qt) — exactly the failure mode the task names                                                                                                                                                                                                                                                                                                                                                                                            | DE-bound, not a target                                                                                              |

## Repro harness

The PoC harness isolates at three levels: **bus** (a private session bus, so the live
KeePassXC on the real bus is untouchable), **filesystem** (scratch XDG dirs), and
**display** (environment variables removed, and inside a container: no display exists
to leak).

### On the host (fast loop)

```sh
# scratch tree; nothing below it touches the real $HOME state
POC=/tmp/opencode/poc/<candidate>
mkdir -p $POC/{config,data,state,runtime}

env -u DISPLAY -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE \
    XDG_CONFIG_HOME=$POC/config XDG_DATA_HOME=$POC/data \
    XDG_STATE_HOME=$POC/state XDG_RUNTIME_DIR=$POC/runtime \
    HOME=$POC \
    dbus-run-session -- bash -c '
      echo "bus: $DBUS_SESSION_BUS_ADDRESS"
      # start the candidate here, then:
      secret-tool store --label=poc service poc attribute poc
      # then pipe "poc-value" on stdin
      secret-tool lookup service poc attribute poc
    '
```

`dbus-run-session` spawns a private `dbus-daemon`; nothing the candidate registers can
be seen from the real user bus (verified: the private bus address is
`unix:path=/tmp/dbus-…`). The live KeePassXC keeps `org.freedesktop.secrets` on
`/run/user/31893/bus` and cannot be collided with.

### In a podman container (strong isolation)

On this host podman's system storage config points at a root-owned directory, and the
user is not a writer of it; a user-owned override makes rootless podman work (verified
by pulling and running `alpine:3.20`):

```sh
PM=/tmp/opencode/pm
cat > $PM/storage.conf <<EOF
[storage]
driver = "overlay"
graphroot = "$PM/storage"
runroot = "$PM/run"
EOF
export CONTAINERS_STORAGE_CONF=$PM/storage.conf
podman run --rm -it \
  --mount type=bind,source=/nix/store,target=/nix/store,readonly \
  debian:trixie-slim
```

Inside, everything needed comes from the **host nix store, read-only** (NixOS binaries
are self-contained — they find their own glibc through RPATH): `dbus`, `libsecret`
(`secret-tool`), the candidate package from `nix build`. The container has no display
at all — H1/H2 are tested under the hard condition, not a variable-removal condition.
The container also has no `/dev/hidraw`: the YubiKey cannot be reached from the PoC by
accident (by design, the stub age key stands in; the real-YubiKey chain was measured
on the host, see below and [recommendation.md](recommendation.md)).

## Per-candidate notes with sources

### rosec

- Unit templates in the source: `Type=dbus`, `BusName=org.freedesktop.secrets`,
  `WantedBy=default.target`, with a comment that it is **deliberately not** ordered
  after `graphical-session.target` (`rosec/src/enable/templates/rosecd.service`,
  report `rosec.md` §3).
- No session bus at all is handled: the default feature `private-socket` embeds a
  D-Bus broker (`busd`) at `$XDG_RUNTIME_DIR/rosec/bus` and a watcher later migrates
  to the real session bus when it appears (`rosecd/src/bus.rs` `establish_connection`,
  `session_bus_watcher`; report `rosec.md` §3/§6). This is unique among the
  candidates: rosec does not need _any_ session bus to start.
- Prompt ladder (source `rosec-secret-service/src/state.rs` 790–975,
  `prompt_env.rs`; report `rosec.md` §6): 1) `SSH_ASKPASS` in the daemon env → the
  daemon runs that program with the prompt text as argv[1] and reads one stdout line; 2) `[prompt] backend = "<binary>"` config: the daemon writes a JSON request to
  stdin, reads `{"<field_id>": "<value>"}` from stdout — a fully custom, headless
  prompter contract; 3) `rosec-prompt --tty` (rpassword on the TTY), resolved as a
  sibling binary; 4) hard error naming the CLI command. **No silent dialog, no hang.**
- Non-interactive unlock channels for an external helper (same §6): D-Bus
  `org.rosec.Daemon.AuthProviderFromPipe(provider_id, pipe_fd)` — the PAM helper uses
  exactly this (fd-passed password, nothing on the wire), plus the two above, plus
  key-wrapping (`rosec provider add-password`) so any derived secret becomes a valid
  unlock password.

### gopass secret-service (built-in, v1.17.4) and gopass-secret-service (nikicat, v0.3.1)

- Both: pure Go, no CGo, no display/portal dependency (ADR A-11 "Feasibility
  Summary"; report `gopass-secret-service.md` §6).
- Unit target: gss writes `WantedBy=default.target` (headless-correct). gopass'
  `secret-service install` writes `After/PartOf/WantedBy=graphical-session.target` —
  **the only headless wart**, fixed by a unit override or by D-Bus activation
  (`~/.local/share/dbus-1/services/org.freedesktop.secrets.service`, `Exec=gopass
secret-service serve`, which works headless as long as a session bus exists).
- Locked-state behaviour: never a D-Bus Prompt (infrastructure exists, call sites do
  not — all ops return `"/"`); the read goes to the age backend. Age backend locked:
  YubiKey = physical touch (the hardware is the prompt, no TTY needed); or agent
  socket; or keyring passphrase via pinentry/stdin (`GOPASS_AGE_STDIN_PASSPHRASE`
  forces stdin — documented for non-TTY automation); if nothing works, the read fails
  cleanly. **GPG backend note:** the reports document a known startup deadlock with
  `pinentry-gnome3` and a GUI-less environment — for this task the age backend is the
  only acceptable choice.
- No container-grade repro was needed for the daemon itself (`secret-tool` +
  `dbus-run-session` is sufficient), but the built-in daemon **is not in the pinned
  nixpkgs gopass (1.17.3)** — the PoC must use gopass ≥ 1.17.4 (report
  `gopass-secret-service.md` §1; locked-nixpkgs grep in [research.md](research.md)).

### oo7

- Daemon unit ships from nixpkgs `oo7-server`: `Type=dbus`,
  `BusName=org.freedesktop.secrets`, `PrivateNetwork=yes`, `ImportCredential=…`,
  plus the `dbus-org.freedesktop.secrets.service` activation symlink (report
  `oo7-bitw-nixpkgs.md` §1, with the upstream unit file cited:
  `server/data/oo7-daemon.service.in`).
- Prompt behaviour without a DE is designed-in, not patched-over: the daemon
  delegates prompts to a prompter chosen by session type; with no graphical session it
  calls `org.freedesktop.secrets.CliPrompter.Prompt`, a D-Bus interface owned by the
  running `oo7-cli` command (which prints an `rpassword` prompt on the TTY and returns
  the secret over a socketpair fd). A client that is _not_ `oo7-cli` while the
  keyring is locked gets `Completed(dismissed=true)` — a clean failure, no hang
  (source `server/src/prompt/mod.rs`, `server/src/service/mod.rs:446-466`,
  `cli/src/main.rs:20-52, 548-551`; report `oo7-bitw-nixpkgs.md` §1 "Headless").
- External unlock is **start-time only**: `oo7-daemon --login` (password from stdin —
  pipeable from a sops helper), the `oo7-daemon-login` helper socket (sealed memfd),
  PAM (`pam_oo7`), or systemd-creds (`$CREDENTIALS_DIRECTORY`, TPM2 via systemd-homed).
  There is no mid-session D-Bus unlock-with-secret (the spec's `Unlock` takes object
  paths and returns a Prompt — implemented per spec, but that Prompt path in a
  non-graphical session means oo7-cli or dismissal). This is the main ergonomic
  difference to rosec.
- Version caveat: locked nixpkgs has **0.6.0**; `--login`/helper socket/v1 keyrings
  are 0.7.x-era features (ArchWiki + release notes; report §1). The PoC must use
  ≥ 0.7.1 to exercise the documented headless channels.

### KeePassXC 2.8.0 (the incumbent on this host)

- Headless boot is real and already in production **here**: `keepassxc --pw-stdin
<db>` started by a systemd user unit, master password fed from the pass store by an
  expect wrapper (`packages/kdn-keepass/`, measured: PID 29540 up since 2026-11-10,
  registered on the user bus as `org.freedesktop.secrets`).
- But the provider _is_ the GUI process: the bridge is constructed in
  `MainWindow::setup` (`src/gui/MainWindow.cpp:228`); there is no standalone provider
  binary in 2.8.0. `QT_QPA_PLATFORM=offscreen` works for the unlocked steady state
  (the offscreen segfault was fixed in 2.8.0, CHANGELOG #13761, guard
  `src/gui/osutils/nixutils/NixUtils.cpp:76-83`).
- The locked state is the failure (report `keepassxc.md` §3/§4): every prompt is a Qt
  dialog; defaults make it worse — `FdoSecrets/UnlockBeforeSearch=true`
  (Config.cpp:207) hangs the D-Bus dispatch thread in `QEventLoop::exec()` on a
  Search against a locked DB. No programmatic answer exists in 2.8.0.
- Headless regime, exactly four settings: `FdoSecrets/Enabled=true`,
  `FdoSecrets/ConfirmAccessItem=false`, `FdoSecrets/UnlockBeforeSearch=false`,
  `Security/LockDatabaseIdle=false` (this host already sets the lock settings false;
  the search/confirm ones are already set false here too — measured in
  `~/.config/keepassxc/keepassxc.ini`), plus `Restart=always` + re-`--pw-stdin` on
  start so a crash self-heals. Even then: after a `Service.Lock` by any client, the
  provider is dead-on-arrival until a human re-unlocks (via the GUI or a process
  restart). Upstream fix in flight: **PR #8591** (bridge separated from the GUI,
  milestone 2.9.0).

### Reference: gnome-keyring / KWallet

- gnome-keyring daemon starts headless (D-Bus activation, in nixpkgs with 3
  activation files; systemd unit `-Dsystemd=disabled` in the nixpkgs build), but its
  unlock prompt is a **GTK dialog** — the task's named failure. (Report
  `oo7-bitw-nixpkgs.md` §3.)
- ksecretd (KF6 kwallet) implements the secret-service interface with a **Qt wizard
  prompt** and is started by KDE autostart only (no `org.freedesktop.secrets`
  activation file). Same category. (Same table row.)

## Open risks to check in the PoC phase

1. rosec's prompt ladder and `AuthProviderFromPipe` were verified **from source**, not
   executed (0.0.34 vs the researched 0.0.40; report drift is known: socket path in
   README vs source — the source path is `$XDG_RUNTIME_DIR/rosec/agent.sock`).
2. gopass built-in daemon: < 1 month old; the PoC runs the exact shipped nixpkgs
   binary; expect early bugs (first post-tag fix was a bus-name ordering bug #3662).
3. oo7: the TTY prompter only works through `oo7-cli`; plain `secret-tool` clients get
   a dismissed prompt while locked (by design). For SSH-driven consumers that is
   acceptable only with start-time unlock.
4. KeePassXC: the PoC must not touch the real instance. Use a throwaway KDBX in
   scratch dirs on a private bus (and/or a container), never `~/Nextcloud/...kdbx`.
