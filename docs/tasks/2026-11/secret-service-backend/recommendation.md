---
type: Decision
description: Chosen route (gopass secret-service + age/YubiKey + SSH feeder, rosec as the verified alternative), design of the pass/sops plug-in, unlock authorisation, packaging and sync.
status: open
authored_by: agent
timestamp: 2026-11-14T01:40:00+01:00
---

# Recommendation and design

Inputs: [research.md](research.md), [research.headless.md](research.headless.md),
[research.storage.md](research.storage.md), [research.ssh-agent.md](research.ssh-agent.md),
the five full reports in the session journal, and the local measurements on `oams`
(YubiKey sops chain proven; KeePassXC 2.8.0 running as the incumbent; podman isolation
made to work).

## The route

**Primary: `gopass secret-service` (gopass ≥ 1.17.4, nixpkgs) with the age backend,
a YubiKey age identity as the unlock factor, and a small SSH feeder service.**
It is the smallest viable route that satisfies every hard requirement _and_ the
task's storage wish:

- it is a real `org.freedesktop.secrets` implementation (collections, items, plain +
  DH sessions, GetSecrets, exact-match SearchItems, `default` alias, kernel-keyring
  `session` collection) — verified in source (ADR A-11, `internal/secretservice/`);
- **headless by construction**: pure-Go daemon, no display, no portal, no D-Bus
  prompts; unlock happens in the age backend;
- **the storage is the task's preferred shape**: one age-encrypted file per secret
  under `$XDG_DATA_HOME/gopass/stores/root/secret-service/`, a file tree that
  Syncthing/Nextcloud sync without lock files and that a human can inspect
  (ciphertext only);
- **the unlock factor is the same sops/age/YubiKey chain this tree already uses**:
  `age-plugin-yubikey` is a documented first-class recipient in gopass, the hardware
  touch _is_ the prompt, and the age agent caches identities for the session. This
  host's YubiKey chain (sops + age 1.3.2 + age-plugin-yubikey 0.5.1, slot 3, no PIN,
  no touch) was measured working;
- **no online binding** on the local path (age is embedded; the only network features
  are opt-in: self-update, HIBP audit, GitHub SSH-key fetch — and `core.autosync`
  must be off);
- packaging is a pin bump: nixpkgs master already ships gopass 1.17.4; this flake's
  pinned nixpkgs has 1.17.3 (predates the daemon), so the route needs the pin bump
  that the flake-update procedure already covers — or a two-line overlay.

**Runner-up: rosec** (0.0.34 in the pinned nixpkgs / 0.0.40 upstream). It is the
stronger project on three axes — first-class headless design (embedded private bus,
fail-closed prompt ladder), **native SSH agent** with `allowed_signers`, and
three non-interactive unlock channels (`AuthProviderFromPipe`, `SSH_ASKPASS`, custom
prompt backend). It loses on the storage shape (single JSON vault file, not a tree),
on packaging right now (the pinned 0.0.34 derivation **fails to build from source**
here: `zstd-sys` build-script error; the upstream 0.0.40 release ships static musl
binaries, so a small derivation or a flake input is needed), and on bus factor
(effectively one maintainer, 0.0.x, 47 stars). If the PoC shows the gopass daemon
misbehaving (it is < 1 month old), rosec is the switch — the PoC plan tests both.

**Keep as the incumbent, do not migrate yet: KeePassXC 2.8.0.** It already runs
headless on this host (never-locked regime, password fed from the pass store, DB in
Nextcloud). It passes the hard requirements _under that regime_ but cannot use a
custom storage backend (sops only protects the KDBX master password) and has no TPM
path; its bridge is GUI-coupled until upstream PR #8591 (milestone 2.9.0). It stays
the fallback until the chosen route has run for a while.

**Rejected, with evidence:** mdellweg (dead deps + ten code-confirmed spec bugs,
including the three that plausibly broke this repo's tools — see
[research.md](research.md)); yousefvand (archived, panic on a libsecret path, no
store seam); bitw (online binding); gnome-keyring/KWallet (DE-bound GUI prompts);
grimsteel/pass-secret-service (not chosen as the route, but **the best fork base** if
a custom `SecretStore` backend becomes the goal — see "Fork seam" below).

## How `pass`/sops plug in

- **The store** is gopass' age backend: one age-encrypted file per item. The same
  primitives as sops (age), the same identity file format (`AGE-PLUGIN-YUBIKEY-…`),
  the same plugin (`age-plugin-yubikey`). No conversion layer.
- **Existing pass material**: gopass can mount a pass-compatible store; a one-time
  `gopass init --crypto age --storage fs` creates the tree; migration of the existing
  `~/.password-store` is a `gopass` import (out of scope for this task).
- **sops files stay sops files**: they are a different format for configuration
  secrets, not for the live store. The helper below uses sops to protect the unlock
  material; the store itself uses age directly.
- **`core.autosync` must be `false`** (or use the `fs` storage backend) so the daemon
  never pushes a git remote unattended. This is the one online trap in gopass.

## How the YubiKey/TPM2 unlock helper authorises the daemon

Two layers, both already proven on this host:

1. **Per-store identity (the hardware factor).** The gopass age identity is a YubiKey
   identity (`age-plugin-yubikey`). On the first read after boot the plugin asks for
   the key (touch or PIN depending on the slot policy; this host's slot 3 needs
   neither), decrypts the item, and the age agent caches the identity for
   `age.agent-timeout`. No TTY, no display, no password string anywhere.
2. **Keyring envelope (v1.17.4, optional).** `age.keyring-identities` can point at a
   hardware-plugin identity that protects the whole identity keyring; the agent then
   caches the software identities. Documented, but "YubiKey and TPM plugins may
   support this flow but have not been tested" — use only after a manual test.
3. **sops as the bootstrap for non-hardware secrets.** Anything that must stay a
   password (e.g. a `GOPASS_AGE_PASSWORD` for a software keyring) is stored in a sops
   file encrypted to the YubiKey age recipient; the unit's `ExecStartPre` runs
   `sops -d` and hands the value to the daemon via the documented stdin/env channel.
   This is the same helper shape KeePassXC/oo7 would need, so it is available as a
   fallback if the age-plugin route ever regresses.
4. **TPM2**: the plugin mechanism is generic (`age-plugin-tpm` is in nixpkgs), but
   gopass documents it as untested for the keyring-envelope flow. On this host there
   is no TPM in the target machine (`oams` has none; the future mini-PC does), so the
   TPM path is recorded as "mechanism exists, unverified" and is not the PoC target.

## How the service is packaged and started at login without a display

- **Package**: `pkgs.gopass` ≥ 1.17.4. With the pinned flake nixpkgs (1.17.3) the
  route needs the routine flake update (or a `pkgs/by-name`-shaped overlay pinning
  1.17.4). No patching, no fork.
- **Unit** (user scope, headless-correct): override the unit that
  `gopass secret-service install` writes so that it is not tied to
  `graphical-session.target`:

  ```ini
  [Unit]
  Description=org.freedesktop.secrets (gopass)
  PartOf=default.target
  After=default.target

  [Service]
  Type=dbus
  BusName=org.freedesktop.secrets
  ExecStart=%h/.nix-profile/bin/gopass secret-service serve
  Restart=on-failure

  [Install]
  WantedBy=default.target
  ```

  plus the D-Bus activation file
  `~/.local/share/dbus-1/services/org.freedesktop.secrets.service`
  (`Exec=gopass secret-service serve`) so clients on the session bus start it on
  demand. The unit needs the user's session bus (systemd user manager provides it);
  if the host must serve secrets before any login, `loginctl enable-linger <user>`.

- **Environment**: `GOPASS_CONFIG`/`GOPASS_HOMEDIR` if the store is not in the default
  XDG path; `age.agent-enabled=true`, `age.agent-timeout=…` in the gopass config;
  `core.autosync=false`.
- **SSH feeder** (the only local code): a user service `gopass-ssh-feed.service` that
  runs on the same unlock event (or on a timer/path trigger) and executes
  `gopass cat <ssh item>` → `ssh-add -t <ttl>` in the running OpenSSH agent, and
  a lock counterpart that runs `ssh-add -D` and removes the generated
  `allowed_signers`. ~50 lines, no daemon.

## Which sync transport

**Syncthing or Nextcloud file sync of the gopass store tree** (`fs` backend, no git
remote, or git without autosync). Rationale: per-file ciphertext, no lock file, a
lost file loses one secret, and both transports are already used in this tree
(Nextcloud carries the KDBX today; Syncthing runs on the host). **litestream is not
used** — no candidate stores the secret material in SQLite, so litestream has nothing
to replicate.

## Fork seam (only if a custom backend is ever needed)

- **Preferred fork base: grimsteel/pass-secret-service** — a real
  `SecretStore` async trait (`src/secret_store/mod.rs`, ~20 methods) with the D-Bus
  layer generic over `Box<dyn SecretStore>`; an age/sops file-tree backend is a new
  impl (`read_secret`/`create_secret`/`set_secret` exec the external helper), drop
  `src/pass.rs`, move the plaintext `*.redb` metadata into the encrypted files
  (issue #12), keep the working `Type=dbus` units. 3,742 Rust LOC, GPL-3.0, active.
- **rosec provider seam** (if rosec is chosen and a sops-tree provider is wanted):
  `rosec-core` `Provider` trait + the documented Extism WASM guest contract; a native
  `rosec-sops` crate registered in `build_providers`, or a WASM guest using the
  `file_read` host import. No D-Bus/agent code touched.
- **gopass**: no fork needed for the storage — the store is gopass itself. A fork
  would only be justified to change the daemon (e.g. implement Prompt objects or key
  eviction on lock).

## What the PoC must prove (summary; executable plan in the session journal)

PoC candidate selection and the reason each candidate was accepted or rejected **for the PoC**:
`poc/selection.md` in the session journal (gopass and rosec full, oo7 light/non-blocking,
KeePassXC dropped by the user, the rest rejected in research).

For **gopass** (primary) and **rosec** (runner-up), under isolation (private bus +
scratch XDG, container where possible), against the task's acceptance list:

1. `secret-tool` store/read round-trip in a headless session (no display).
2. Ciphertext on disk; unlock through the sops/age helper (stub age key standing in
   for the YubiKey; the real YubiKey chain is already measured); a locked store fails
   cleanly, not with a hang.
3. The layout copies to a second "host" and reads the same secret; no lock-file
   conflict.
4. One SSH key into an agent with no interactive `ssh-add`; sign a commit; verify it
   (rosec: its own agent + `allowed_signers`; gopass: the feeder service).

A lighter PoC on **oo7** and **KeePassXC** verifies the headless claims for the
runner-up and the incumbent (no SSH, no custom storage).

## PoC outcome (2026-11-14)

The recorded runs (session journal `poc/results.md`, `poc/summary.md`) change the ranking:

- **rosec is the primary route** — the only candidate that interops with the **deployed**
  libsecret 0.21.8.2 (30/30 DH sessions; gopass fails 20/30 with `invalid DH public value
  length: 129`) and both external unlock channels work headlessly (`AuthProviderFromPipe`,
  `SSH_ASKPASS`). Conditions: the helper must always be configured (a locked read without it
  hangs), packaging must be solved (pinned nixpkgs 0.0.34 fails to build; 0.0.40 release binary
  is not a package), and a real-YubiKey smoke test is still owed.
- **gopass is a fallback only** with a DH fix (patch the 129-byte handling, or pin libsecret to
  0.21.7). Its unlock design is proven (`pinentry-kdn` + sops).
- **grimsteel/pass-secret-service is the custom-backend fork base** — the `SecretStore` seam is
  24 async methods plus a one-line wiring change; the PoC impl is ~330 lines with all encryption
  delegated to the external `age`/sops helper (compile not completed in this session).
- oo7 was not PoC'd (non-blocking); KeePassXC was dropped by the user (already deployed, does not
  meet the headless requirements).
