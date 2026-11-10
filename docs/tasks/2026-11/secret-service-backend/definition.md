---
type: Task
description: Choose or build a headless FreeDesktop Secret Service implementation that runs with no desktop environment and can use a custom storage backend (pass, sops).
status: open
authored_by: agent
timestamp: 2026-11-10T07:58:01+01:00
---

# Headless Secret Service with a custom storage backend

Specification: <https://specifications.freedesktop.org/secret-service/latest/>

## Problem

This host must provide `org.freedesktop.secrets` to command-line tools (git credential helpers, `gh`,
editors, CLI agents) on machines that have **no desktop environment**. KeePassXC works as a Secret
Service provider and is independent of a DE in the sense that it does not need GNOME or KDE, but it
has never been verified headless here, and it stores secrets in its own KDBX database rather than in
the storage this tree already owns (`pass` and sops).

A previous attempt used `mdellweg/pass_secret_service` (Python). It was outdated and broke several
tools. The failure modes were never diagnosed: it is unknown whether the API surface was incomplete
or the applications expected GNOME-keyring-specific behaviour.

## Hard requirements

1. **Headless.** Runs with no X11, no Wayland, no `DISPLAY`, no `WAYLAND_DISPLAY`, no session bus
   beyond the systemd user bus. Every unlock, prompt and error path must work from a TTY or an SSH
   session. A GUI dialog that cannot be shown counts as a failure.
2. **Independent of a desktop environment.** No GNOME or KDE libraries, no `gnome-keyring` or
   `kwallet` daemon, no XDG Desktop Portal dependency for core operation. The service starts from
   `systemd --user` (socket activation preferred) and survives a session without a graphical login.
3. **No online service.** The provider must not require a remote vendor account or a hosted API.
   Sync is the owner's own transport (Nextcloud, Syncthing, `litestream`), never a third-party
   service the daemon talks to itself.
4. **Encrypted at rest.** The stored form is never plaintext. A stolen disk, a synced folder or a
   backup must be useless without the unlock material.
5. **Unlock by YubiKey and/or TPM/TPM2.** The unlock flow must accept a hardware factor. A
   `sops`/`age`-based unlock helper is the expected route: the daemon receives an already-unlocked
   plaintext view or a key from a helper, and the helper decides whether the YubiKey, the TPM, or
   both authorise the unlock.
6. **Spec conformance.** The implementation must cover the collection, item, session, prompt, alias,
   search and lock parts of the specification. At minimum the calls used by `libsecret`,
   `secret-tool`, the `git` credential helper and `gh` must work.
7. **Session collection semantics.** `session` collection, `plain` and `dh` sessions, `GetSecrets`,
   `SearchItems` with attributes, `default` alias, and `Lock`/`Unlock` must behave as the spec says,
   not as one application happens to expect.
8. **No desktop-only unlock.** An unlock that needs a YubiKey/PIN can be requested through a
   command-line helper or PAM, not through a GTK/Qt dialog.

## Nice to have

- **Maintainability is tradeable.** A small codebase that is easy to audit and fork is welcome, but
  not required. A ready project with extensibility/forkability, popularity, respectability and
  longevity may win over a tiny one. Prefer the combination that survives years of maintenance:
  an established upstream with a storage extension point beats a smaller but unmaintained
  implementation.
- **Pluggable storage backend.** A hard-coded format is acceptable if it is encrypted and syncable.
  A backend interface is a bonus, or a low-effort fork of a small implementation.
- **File-tree storage.** One file per item, so Syncthing and Nextcloud sync it without special
  handling and a human can inspect the tree (still encrypted).
- **Sync-friendly layout.** No lock file that breaks Syncthing; no single mutable SQLite file unless
  `litestream` is the chosen replication mechanism. Document which of Nextcloud, Syncthing or
  `litestream` each storage layout supports.
- **Low-tech recovery.** A machine can be brought up from the synced copy plus the unlock material,
  with no export step.

## Candidates

Initial list only. None of these has been evaluated yet. The "online binding" column in the research
must reject anything that needs a vendor service; a self-hosted server is still an online service
for requirement 3.

- **KeePassXC** — existing provider; verify whether it can run headless without a GUI, whether its
  KDBX file (one encrypted file) syncs cleanly, and whether YubiKey/TPM unlock exists there.
- **oo7** — Rust daemon plus portal and PAM module; check whether the daemon is usable without a DE,
  where it keeps state, and whether an external unlock helper is possible.
- **gopass-secret-service** (`nikicat`) — Go, gopass-backed; gopass is a file tree with git sync, so
  it matches the sync wish if the daemon stays local.
- **yousefvand/secret-service** — Go, file-backed, small; possible base for a fork with a custom
  backend loader and an encrypted file tree.
- **grimsteel/pass-secret-service** — pass-backed; check whether it is the maintained successor of
  the Python one and whether `pass` (file tree, git-syncable) is used directly.
- **mdellweg/pass_secret_service** — the known-fault case from the past; keep as a comparison point,
  not as a default.
- **`bitw`** — Bitwarden-based; note only, probably remote-service bound.
- **`gnome-keyring`, `KWallet`** — reference implementations, but both are DE-bound. Use for
  conformance comparison, not as a target.

## Research questions

For every candidate:

1. Maintenance: last release, commit cadence, open issues, licence.
2. Popularity and reputation: users, downstream packaging (nixpkgs, distro packages), known security
   reports.
3. API completeness: which spec interfaces are implemented; what is missing; does it implement
   prompts, sessions, aliases, search and locking.
4. Correctness: tests, conformance checks, known incompatibilities with common clients.
5. Extensibility and maintainability: storage abstraction, code size, language, dependency weight,
   difficulty of adding a backend, and the trade-off between a small forkable codebase and a larger,
   established project with a longer maintenance record.
6. Headless behaviour: does any path require a display, a portal or a DE daemon.
7. Packaging: available in nixpkgs, build inputs, systemd user unit, socket activation.
8. Storage format: what is on disk, is it encrypted, is it one file or a tree, what unlocks it.
9. Sync: can the on-disk form be synced by Nextcloud, Syncthing, or `litestream` without a conflict
   or a lock file.
10. Unlock: can it take a key from an external helper (sops/age, YubiKey, TPM2), or does it own the
    prompt and require a display.
11. Online binding: does it call a remote service, need an account, or ship telemetry.

## Known fault case to document

`mdellweg/pass_secret_service` was used in the past and broke tools. The research must record the
actual failure modes instead of a general "it was buggy". Candidate causes to check:

- missing `session` collection or an incorrect `default` alias;
- incomplete `Prompt` handling (`org.freedesktop.Secret.Prompt`);
- `dh` session support missing or wrong, so `libsecret` fell back or failed;
- `SearchItems` attribute matching semantics;
- `Lock`/`Unlock` returning before the collection is usable;
- applications assuming GNOME-keyring extensions outside the spec.

## Deliverables

Research phase (this task, until a decision):

- `research.md` — one row per candidate against the questions above, with the commands and sources
  used, and a short "would fork / would wrap / reject" verdict.
- `research.headless.md` — a focused note on how each candidate behaves with no DE, including exact
  repro commands (`systemctl --user`, `dbus-run-session`, `secret-tool`).
- `research.storage.md` — the on-disk form of each candidate: encryption, file tree vs single file
  vs SQLite, what Syncthing/Nextcloud/`litestream` can sync, and how an external `sops`/`age` helper
  unlocks it.
- A recommendation with the smallest viable route: reuse, fork, or a thin wrapper over
  `libsecret`/D-Bus, including where the storage abstraction would go if a fork is needed.
- A proof-of-concept plan: how `pass`/sops plug in, how the YubiKey/TPM2 unlock helper authorises the
  daemon, how the service is packaged and started at login without a display, and which sync
  transport is used for the chosen layout.

Implementation, packaging and migration are **out of scope** for this task until the research lands.

## Acceptance

The task is done when `research.md` answers every research question, names one route, and the route
has a tested PoC sketch (commands and expected calls) that:

- stores and reads one secret through `secret-tool` in a headless `dbus-run-session`;
- keeps the store encrypted on disk and unlocks it through the `sops`/`age` helper with the YubiKey or
  TPM2 (a stub helper is enough for the sketch);
- syncs the chosen layout with at least one of Nextcloud, Syncthing or `litestream` without a
  conflicting lock file.

A candidate that cannot pass the headless check, requires an online service, or cannot be encrypted
at rest is rejected in writing, with the evidence.

## References

- Specification: <https://specifications.freedesktop.org/secret-service/latest/>
- NixOS Wiki, Secret Service: <https://wiki.nixos.org/wiki/Secret_Service>
- KeePassXC Secret Service discussion: <https://github.com/keepassxreboot/keepassxc/discussions/8016>
- oo7 — the ArchWiki page names the daemon, portal, CLI and PAM module:
  <https://wiki.archlinux.org/title/Oo7> (find the upstream repository during research)
- `nikicat/gopass-secret-service`: <https://github.com/nikicat/gopass-secret-service>
- `yousefvand/secret-service`: <https://github.com/yousefvand/secret-service>
- `mdellweg/pass_secret_service`: <https://github.com/mdellweg/pass_secret_service>
- `grimsteel/pass-secret-service`: <https://github.com/grimsteel/pass-secret-service>
