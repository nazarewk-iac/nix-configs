---
type: Research
description: Full evaluation of rosec as the headless Secret Service implementation, including its custom-provider (storage backend) seam.
status: open
authored_by: agent
timestamp: 2026-11-14T12:00:00+01:00
---

# rosec — full evaluation

Candidate: [jmylchreest/rosec](https://github.com/jmylchreest/rosec), evaluated at
**v0.0.40** (released 2026-11-13). Companion material: the full source-level report in the
session journal (`research/rosec.md`), the PoC results (`poc/results.md`, `poc/summary.md`),
and the plan review (`poc/review-plan.md`). This file is the consolidated evaluation, with the
PoC findings folded in and clearly marked.

## 1. What it is

| Item        | Value                                                                                                                                                                                           |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Project     | Rust workspace: `rosecd` (daemon), `rosec` (CLI), `rosec-prompt`, `pam_rosec.so` + `rosec-pam-unlock`, `rosec-uhid` (optional FIDO2 passkey broker)                                             |
| Scope       | `org.freedesktop.secrets` provider, its own SSH agent, TOTP files, optional FIDO2 passkeys, PAM unlock, FUSE tree                                                                               |
| Version     | 0.0.40 (2026-11-13); repo created 2026-02-24; 653 commits                                                                                                                                       |
| Licence     | MIT (the Proton Pass provider crate is GPL-3.0-or-later)                                                                                                                                        |
| Maintenance | effectively solo (`jmylchreest` 623/633 commits), 47 stars, no SECURITY.md, no published advisories                                                                                             |
| Packaging   | nixpkgs `pkgs.rosec` 0.0.34 (pinned here; **fails to build from source** on `zstd-sys`); AUR `rosec-bin` updated the same day as each release; no flake; upstream issue #2 tracks Nix packaging |
| Size        | ~77k lines of Rust across the workspace (largest: secret-service 14k, wasm 9.5k, CLI 7.9k, core 6.7k, daemon 4.7k, vault 3.6k, ssh-agent 663)                                                   |

## 2. Architecture

- **`rosecd`** is the long-lived user daemon. It hosts the D-Bus service, the SSH agent, the
  FUSE mounts and the provider registry. It claims `org.freedesktop.secrets` with
  `DO_NOT_QUEUE` (fails loudly with owner info if taken) and the portal name
  `org.freedesktop.impl.portal.desktop.rosec` (non-fatal).
- **Start paths**: D-Bus activation (`org.freedesktop.secrets.service` written by `rosec enable`),
  a socket unit (`rosecd.socket`), or a plain user unit. The shipped unit is `Type=dbus`,
  `BusName=org.freedesktop.secrets`, `WantedBy=default.target` and is **deliberately not** ordered
  after `graphical-session.target`.
- **Session bus is optional**: the default `private-socket` feature embeds a D-Bus broker
  (`busd`) at `$XDG_RUNTIME_DIR/rosec/bus` and migrates to the real session bus when it appears
  (`session_bus_watcher`). The PoC used `--socket … --no-migrate` and needed no session bus at
  all.
- **Providers** are the storage backends (section 5). Native ones are registered in
  `build_providers` (`rosecd/src/main.rs`); WASM ones are Extism guests with policy sidecars.
- **`rosec enable`** writes user-local files only: the D-Bus activation file, the systemd user
  units, and (with `--mask`) masks gnome-keyring. It is the only command that touches the host's
  service directories; a PoC must not run it.

## 3. Spec conformance

| Interface / feature                                                                                                                          | Status | Notes                                                                                                                                                                                            |
| -------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Service`: `Collections`, `OpenSession`, `CreateCollection`, `SearchItems`, `Unlock`, `Lock`, `GetSecrets`, `ReadAlias`, `SetAlias`, signals | ✅     | verified in `rosec-secret-service` source                                                                                                                                                        |
| `Collection`: `Items`, `Label`, `Locked`, `Created`, `Modified`, `Delete`, `SearchItems`, `CreateItem`, signals                              | ✅     | —                                                                                                                                                                                                |
| `Collection`: `GetSecrets`, `ClearSecret`, `Lock`, `Unlock`                                                                                  | ❌     | missing (open issue #106); `GetSecrets` exists only on `Service`                                                                                                                                 |
| `Item`: `Locked`, `Attributes`, `Label`, `Created`, `Modified`, `Delete`, `GetSecret`                                                        | ✅     | `GetSecret` is session-aware                                                                                                                                                                     |
| `Item.SetSecret`                                                                                                                             | ⚠️     | present but always `NotSupported` ("use CreateItem with replace=true", issue #105)                                                                                                               |
| `Session`: `Close`; `plain` + `dh-ietf1024-sha256-aes128-cbc-pkcs7`                                                                          | ✅     | spec DH: RFC 2409 group 2, HKDF-SHA256 no salt, AES-128-CBC/PKCS7; client public values range-checked and **variable-length accepted** (PR #90) — the reason it interops with libsecret 0.21.8.2 |
| Session binding                                                                                                                              | ✅     | sessions bound to the caller's unique name, torn down on disconnect                                                                                                                              |
| `SearchItems` semantics                                                                                                                      | ✅     | exact, AND-ed attribute equality on SHA-256 hashes; the special key `name` matches the label; a non-standard glob extension exists (`org.rosec.Search.SearchItemsGlob`)                          |
| `default` + `login` aliases                                                                                                                  | ✅     | both registered; `CreateCollection` shim returns the default collection for `default`/`""` and `("/", "/")` for `login`/unknown (gnome-keyring quirk emulated)                                   |
| `Prompt` objects                                                                                                                             | ✅     | full `Prompt`/`Dismiss`/`Completed`; bound to the initiating caller; per-provider serialization; max 3 attempts; 2FA; deferred create/delete; cancelled on client disconnect                     |
| `Lock`/`Unlock`                                                                                                                              | ✅     | return Prompt objects; per-provider idle/max auto-lock; logind `PrepareForSleep` locks; session-lock/logout policies                                                                             |
| `session` (volatile) collection                                                                                                              | ✅     | kernel-keyring backed                                                                                                                                                                            |

**Assessment:** the spec surface is the most complete of the ready-made candidates, with two
documented gaps (Collection-level methods, `Item.SetSecret`) that libsecret/`secret-tool`/`gh`/git
credential helpers do not use. The PoC exercised store/lookup/search with both libsecret
versions and the DH path 30/30 with 0.21.8.2.

## 4. Headless behaviour

- No display, no portal, no DE daemon needed. The unit is not tied to `graphical-session.target`;
  the embedded private bus removes even the session-bus dependency.
- **Prompt ladder** (source `rosec-secret-service/src/state.rs`): 1) `SSH_ASKPASS` from the
  daemon's environment — the daemon runs the program with the prompt text as argv[1] and reads
  one stdout line; 2) `[prompt] backend = "<binary>"` — a fully custom prompter (JSON request on
  stdin, one JSON line on stdout); 3) `rosec-prompt --tty` (a sibling binary, rpassword); 4) a
  built-in `/dev/tty` prompt; 5) a hard error (the message still names a stale `rosec auth`
  command).
- **Measured (PoC)**: with `SSH_ASKPASS` configured, a locked provider unlocked on demand in
  **67 ms** and served the secret. With **no** helper and no TTY, the client blocked until the
  20 s timeout (`rc=124`) — the ladder does not fail fast in that state. **Operational
  consequence: the helper must always be configured in the unit** (`Environment=SSH_ASKPASS=…`,
  or PAM); otherwise a locked read hangs the client.
- The reviewer independently saw a Prompt/`Completed` result-type mismatch
  (`received unexpected result type s … instead of expected o`) on a locked `store`; it did not
  reproduce in the recorded run (which did not attempt a locked store). Treat the locked-write
  prompt path as young and test it before relying on it.

## 5. Providers and storage (the custom-backend seam)

### Built-in providers

| Provider                         | Storage                                                                                              | Notes                                                                                                                                                                                                                                                                                                                                                                                                                |
| -------------------------------- | ---------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **local** (native `rosec-vault`) | single JSON file `~/.local/share/rosec/providers/<id>.vault` + `<id>.vault.meta` + `<id>.vault.lock` | AES-256-CBC payload; vault key wrapped per password with PBKDF2-HMAC-SHA256 (200k default; docs claim 600k — drift) → AES-256-CBC + HMAC; integrity HMAC-SHA256 via HKDF; only the wrapped key on disk; atomic temp+fsync+rename writes; optimistic revision check; single-writer (external replacement forces re-unlock); `.meta` holds labels + **attribute hashes** (not values); `.lock` is a 0-byte fcntl lease |
| Bitwarden PM/SM                  | WASM guest; host-managed offline cache + machine key                                                 | online only                                                                                                                                                                                                                                                                                                                                                                                                          |
| Proton Pass                      | WASM guest (GPL-3.0), read-only                                                                      | online only                                                                                                                                                                                                                                                                                                                                                                                                          |
| KeePassXC `.kdbx`                | WASM guest reading an existing file                                                                  | experimental; write support unverified                                                                                                                                                                                                                                                                                                                                                                               |
| GNOME Keyring                    | WASM guest, read-only                                                                                | migration path                                                                                                                                                                                                                                                                                                                                                                                                       |

Local provider verdict: encrypted at rest, single file, no lock file with content, docs recommend
Syncthing; the PoC confirmed the vault is ciphertext and a copied vault is readable. Single-writer
is the operating rule.

### The custom-provider contract (the differentiator)

`rosec-core/src/lib.rs` defines `pub trait Provider: Send + Sync`:

- **Required**: `id`, `name`, `kind`, `status`, `unlock`, `lock`, `list_items`, `search`,
  `get_item_attributes`, `get_secret_attr`.
- **Optional, gated by `capabilities()`** (default impls): `sync`/`check_remote_changed`,
  `write` (create/update/delete), `ssh` (`list_ssh_keys`/`get_ssh_private_key`),
  `key_wrapping` (add/remove/list passwords), `password_change`, `offline_cache`
  (export/restore), `notifications` (WebSocket), TOTP/FIDO2.

Two integration paths:

1. **Native crate** implementing the trait, registered in `build_providers`. This is how `local`
   is done; a native provider gets the SSH agent and FUSE tree "for free" if it implements the
   `ssh` capability.
2. **Extism WASM guest** (documented, sandboxed): JSON `plugin_fn` contract, path-scoped
   `file_read` host import, a `*.policy.toml` sidecar, a `*.wasm.minisig` signature, host
   allow-lists for network, trust via `[[service.wasm_trusted_key]]` or source-packaged hashes
   (`ROSEC_PACKAGED_PROVIDERS`). More moving parts; suited to untrusted/third-party code.

**What a sops/age file-tree provider would take:** implement the required methods in a native
crate; in `unlock`, read the tree root and the password/key path from the provider config; decrypt
each item on read (link `age` or shell out to `age`/`sops`); serve `list_items` and attributes
from memory; implement `write` if the store must be writable; implement `ssh` if the vault keys
should feed the agent. No D-Bus, prompt, session or agent code changes. The PoC's analogous
exercise on the grimsteel fork measured the same shape at ~330 lines of ordinary Rust, so this is
a **days-not-weeks** job — the effort is in metadata semantics and tests, not in the seam.

**Trade-off vs the local vault:** the local vault is a single encrypted file (simple, atomic,
single-writer); a file-tree provider gives per-item files (better sync granularity, inspectable
tree, sops/age owns the crypto) but is new code you own. For this task the local vault + external
helper already satisfies every hard requirement; the custom provider is a phase-2 option if sync
granularity or reusing existing sops material becomes the priority.

## 6. Unlock by an external helper

| Channel                                                       | How                                                                                        | PoC                                                                                                      |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `org.rosec.Daemon.AuthProviderFromPipe(provider_id, pipe_fd)` | password through a pipe fd (SCM_RIGHTS), never on the D-Bus wire; used by the PAM helper   | ✅ `rosec-pam-unlock` with stdin password unlocked the vault (`provider authenticated via AuthProvider`) |
| `SSH_ASKPASS` in the daemon env                               | the daemon runs the program, reads one stdout line                                         | ✅ 67 ms on-demand unlock after a lock                                                                   |
| `[prompt] backend`                                            | custom binary, JSON request/response                                                       | source-verified                                                                                          |
| `rosec unlock` / `rosec provider <id> unlock`                 | TTY fd-passing or `--gui`                                                                  | source-verified                                                                                          |
| PAM                                                           | `pam_rosec.so` stashes at auth, replays at session; never blocks login                     | source-verified; not run                                                                                 |
| Key wrapping                                                  | `rosec provider <id> password add` makes any helper-derived secret a valid unlock password | source-verified; the natural fit for a sops/age helper                                                   |

Note: transports are line-based, so a raw 32-byte key must be base64/hex-encoded; the PBKDF2 input
itself accepts arbitrary bytes.

## 7. SSH agent

- **Socket**: `$XDG_RUNTIME_DIR/rosec/agent.sock` (source; the README path `rosec/ssh/agent.sock`
  is stale).
- **Started by** `rosecd` (`ssh_fuse = true` default); degrades gracefully without `/dev/fuse`.
- **Unlocked by** provider unlock/sync; **cleared** on lock, autolock, logout, sleep, shutdown.
- **Key types**: ed25519, RSA, ECDSA, DSA, encrypted PEMs; **no FIDO2 `sk-ssh`, no certificates**,
  no `ssh-add` Add/Remove/Lock commands (keys are vault-driven by design).
- **FUSE tree**: read-only, in-memory: `keys/by-name`, `keys/by-fingerprint`, `keys/by-host`,
  `config.d/*.conf` (`IdentityFile`/`IdentityAgent`/`IdentitiesOnly`), and `allowed_signers`
  synthesized from `custom.ssh_signing_principal`, **fail-closed** when locked.
- **Headless signing confirmation**: a per-key `ssh_confirm` policy allows the sign with a warning
  when there is no display and no TTY.
- **PoC status**: agent listing/commit signing was **not completed** (the `$EDITOR`-driven
  `rosec item add --type ssh-key --generate-ssh-key` did not create the item non-interactively in
  the container). Revocation-on-lock passed trivially (nothing loaded). Treat the SSH angle as
  source-verified plus partially exercised, not proven.

## 8. Sync and recovery

- Single vault file + `.meta` + 0-byte `.lock` lease; docs recommend Syncthing/rsync; the PoC
  copied the vault and a second "host" read it (the review noted the recorded B5 query matched the
  original provider, so the copy read is not fully proven).
- Single-writer: the revision check rejects saves after an external replacement; the supported
  pattern is "last file wins + re-unlock on the other side".
- Recovery: `rosec vault snapshot restore` (encrypted snapshots).

## 9. Online binding and telemetry

Local provider: strictly offline (no `sync` capability; the background loop skips it), no
telemetry (grep-verified). Bitwarden and Proton are optional WASM providers with host-enforced
allow-lists.

## 10. Packaging and start at login

- **nixpkgs 0.0.34** (pinned here): symlinkJoin of `rosec-unwrapped` + `pam_rosec.so` + optional
  provider WASMs; `postInstall` runs `rosec enable` with the XDG dirs redirected into the store,
  so the package ships the unit, D-Bus activation and portal registration. **The source build
  currently fails here** (`zstd-sys` build-script error); the PoC used the upstream 0.0.40 static
  musl release (`rosecd`, `rosec`, `rosec-prompt`, `rosec-pam-unlock`), which is not a package.
- **AUR** tracks releases same-day; no flake upstream.
- **Start without a display**: the shipped unit is already headless-correct (`WantedBy=default.target`);
  D-Bus activation is the primary path. For a host that must serve before login, enable linger.
- **Unit hardening constraint**: the template documents directives that must **not** be added
  (NoNewPrivileges/fusermount interplay, `MemoryDenyWriteExecute` for the wasmtime JIT, FUSE
  mount-namespace visibility). A NixOS module must keep the unit close to the template.

## 11. PoC evidence summary (rosec)

| Check                                                             | Result                                                            |
| ----------------------------------------------------------------- | ----------------------------------------------------------------- |
| Owns the name on a private bus, no session bus, no display        | ✅                                                                |
| `secret-tool` store/lookup with libsecret 0.21.7                  | ✅                                                                |
| `secret-tool` store/lookup with libsecret **0.21.8.2** (deployed) | ✅ **30/30 DH sessions**                                          |
| Vault ciphertext at rest, no plaintext                            | ✅                                                                |
| Unlock via `AuthProviderFromPipe` (`rosec-pam-unlock`)            | ✅                                                                |
| On-demand unlock via `SSH_ASKPASS`                                | ✅ 67 ms                                                          |
| Locked read with **no** helper                                    | ❌ client blocked 20 s (no clean error)                           |
| Vault copy readable on a second "host"                            | ⚠️ recorded query matched the original provider; not fully proven |
| SSH agent listing + commit signing                                | ⚠️ item creation via `$EDITOR` failed non-interactively; unproven |
| Real YubiKey through the daemon                                   | not run (stub identity only)                                      |

## 12. Risks and blockers

1. **Packaging gate** — 0.0.34 does not build from source here; 0.0.40 is a release binary. A
   small derivation or a pinned flake input is required before deployment.
2. **Helper-always-on** — without `SSH_ASKPASS`/PAM a locked read hangs the client (measured).
3. **Young prompt path** — the reviewer saw a `Completed` result-type mismatch on a locked store;
   test the locked-write flow before relying on it.
4. **Bus factor** — solo maintainer, 0.0.x, 47 stars; MIT and source-buildable mitigate.
5. **Spec gaps** — Collection-level `GetSecrets/ClearSecret/Lock/Unlock`, `Item.SetSecret`.
6. **Doc/source drift** — agent socket path, PBKDF2 iteration count, stale `rosec auth` message.
7. **SSH limits** — no FIDO2 `sk-ssh`, no certificates; item creation needs an attended or
   scripted `$EDITOR` step.
8. **FUSE dependency** — the `config.d`/`allowed_signers` surface needs `/dev/fuse`; the agent
   socket works without it.
9. **Dependency weight** — wasmtime/Extism in the closure even for local-only use; `ssh-key`
   patched from a git branch (reproducible only via `Cargo.lock`).
10. **Hardware unverified** — the real YubiKey chain was proven separately (sops+age) but not
    through rosec.

## 13. Verdict

**Reuse rosec as the primary route, with three gates: packaging, always-on helper, and a
real-YubiKey smoke test.** It is the only ready-made candidate that interoperates with the
deployed libsecret (30/30 DH) and satisfies the headless unlock requirement through two
independent external channels. Its custom-provider seam is real and clean (a capability-gated
trait plus a documented WASM contract), and a sops/age file-tree provider is a days-scale
addition if the single-file vault ever becomes the limiting factor — but it is **not needed for
the hard requirements**, which the local vault + external helper already meet.

## 14. Extension estimates (YubiKey SSH, multi-file sync, reload)

### 14.1 "No sk-ssh" — what it does and does not mean

rosec's agent does **not** serve FIDO2 resident keys (`sk-ssh-ed25519@openssh.com`,
`sk-ecdsa-sha2-nistp256@openssh.com`) and does not implement OpenSSH's
`sk-provider@openssh.com` agent extension (`rosec-ssh-agent/src/session.rs` intercepts
`Request::Extension` and returns failure). That is a limitation of **rosec's own agent**, not of
the YubiKey: this tree already runs a FIDO2-capable OpenSSH agent
(`kdn.home.ssh-agent.enable`, nixpkgs openssh linked with libfido2), and rosec's agent is a
second, vault-driven agent. You choose per host with `IdentityAgent`, or run both sockets.

**Option 1 — no fork, hours.** Store the sk key **handle** (the `id_ed25519_sk` file: credential
handle + public key, no secret) as a vault item and feed it to the OpenSSH agent at unlock
(`rosec get <item> > 0600 file && ssh-add file`). Signing still touches the YubiKey. Same shape as
the gopass feeder; ~1–2 hours including the item and a unit hook.

**Option 2 — fork rosec's agent, ~1–2 weeks.** The work:

1. Handle the `sk-provider@openssh.com` extension in `rosec-ssh-agent/src/session.rs` (the
   `Request::Extension` hook exists; the response format is documented in OpenSSH
   `PROTOCOL.agent`) — 2–4 days.
2. Signing path: shell out to `ssh-keygen -Y sign -f <handle> -n <namespace>` (drives libfido2,
   prompts for touch) or link `ssh-key`/`libfido2` with the sk feature — 1–2 days.
3. Key model: the provider `ssh` capability currently assumes a private key
   (`get_ssh_private_key`); add an sk key kind (public key + credential id + application) and
   list it from `RequestIdentities` — 1–2 days.
4. Tests with a real YubiKey, confirmation policy, FUSE `allowed_signers` (unchanged — it lists
   public keys) — 1–2 days.

The "read-only from providers, no add/remove protocol" model needs **no change**; the extension is
a sign-only path. Risk: `ssh-agent-lib`'s extension plumbing is usable (it exposes
`Request::Extension` and a `Session::handle` override), but the protocol must be matched exactly.

### 14.2 Multi-file storage syncable with Syncthing/Nextcloud

| Option                             | Work                           | Properties                                                                                                                                 |
| ---------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Single vault as-is                 | **hours** (ops only)           | Syncthing/Nextcloud sync `.vault` + `.meta`; `.lock` is inert; whole-file conflicts, last-write-wins; re-unlock after external replacement |
| Native file-tree provider          | **3–6 days**                   | one age/sops-encrypted file per item; per-item conflicts; still last-write-wins per item; no watcher unless added                          |
| WASM file-tree provider            | **3–6 days + guest packaging** | same, but gets `register_watch` (inotify) from the host → live reload on external change (the KeePassXC provider uses it)                  |
| Native provider + watcher          | **+1–2 days**                  | `notify`-based reload on file change                                                                                                       |
| Export/import script (no provider) | ~1 day                         | not live, fragile — not recommended                                                                                                        |

The provider seam is the same one the grimsteel exercise measured (~330 lines for the core
methods); the extra days are metadata semantics, write/merge behaviour, and tests.

### 14.3 Does rosec reload providers on file changes?

- **Local vault: no.** An external replacement is detected at write time by the SHA-256 revision
  check — `rosec-vault/src/storage.rs:101-102` returns "vault changed on disk; lock and unlock it
  again before writing" — and the `.lock` lease is held while unlocked. After Syncthing replaces
  the file you must `rosec lock` + unlock (or restart the daemon). No automatic reload.
- **WASM providers: yes, if they register a watch.** The host exposes `register_watch`
  (`rosec-wasm/src/host_watch.rs`, `notify`/inotify, path-scoped, coalesced) — the KeePassXC
  provider reloads on save. A WASM file-tree provider can do the same; a native one must add its
  own watcher.
- Provider _config_ changes (`config.toml`) are hot-reloaded by the daemon; that is separate from
  data-file changes.

## 15. Sync-on-read design (per-key reconciliation, no manual lock/unlock, no watcher)

Requirement: per-item reconciliation (like KeePassXC merges entries, not whole files), no manual
lock→unlock, reconciliation at **read/write time** rather than on a file watch.

### 15.1 The design

- **Layout**: one encrypted file per item — `store/<collection>/<item-id>.age` (or `.sops`),
  containing the secret, label, attributes and `modified_at` + `host` metadata; one `_meta` per
  collection; aliases in a single small file.
- **Index**: in-memory `id → (mtime, size, sha256)`. On **every operation** (list, search, read,
  write): `readdir` + `stat` the collection directory; re-read/decrypt only the files whose
  stamp changed; drop removed entries; add new ones. Cost is a directory scan (microseconds for
  hundreds of files), which is exactly the requested "sync upon reads and writes".
- **Writes**: encrypt → temp file in the same directory → `fsync` → `rename` (atomic); update the
  index. Per-item last-write-wins; `modified_at` + `host` detect concurrent edits.
- **Conflicts**: opaque secrets cannot be semantically merged (KeePassXC merges a structured
  database; a secret value has no merge). Per-item granularity makes conflicts rare and scoped;
  a Syncthing conflict copy is surfaced as a separate item (`<id> (conflict <host>)`) or kept as
  the newest with a log line — a policy choice, not a crypto problem.
- **No lease, no global lock, no revision check.** `unlock` loads the identity (age identity /
  wrapped key); `lock` drops it; `unlock_timeout` is provider-defined (return a long duration to
  disable the daemon's 30 s auto-lock). The helper loads the identity at service start, so the
  user never runs lock→unlock.
- **No watcher.** Optional later; not needed for correctness.

### 15.2 Where it fits

| Base                                   | Fit                                                                                                                                                                                                | Work                                                                                                    |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **grimsteel/pass-secret-service fork** | **best fit**: the D-Bus layer calls the `SecretStore` per operation (`list_secrets`, `search_collection`, `read_secret`, …) — **no daemon-wide cache**, so per-operation reconciliation is natural | new `SecretStore` impl + index/scan + conflict policy + tests: **4–7 days**                             |
| rosec native provider                  | good, but the daemon's **`ItemCache`** serves metadata from memory and rebuilds on unlock/sync/TTL — values are read fresh per `get_secret_attr`, metadata can be stale                            | provider 4–7 days **+ a small daemon patch** to invalidate the cache per operation (fork): **5–9 days** |
| rosec WASM provider                    | possible, but age-in-guest + file imports + policy signing                                                                                                                                         | **2–3 weeks**                                                                                           |
| rosec local vault as-is                | not applicable: single file, no per-key reconciliation, manual re-unlock after external replacement                                                                                                | —                                                                                                       |

**Conclusion:** for this requirement the **grimsteel fork is the better base** than rosec. It
already has the right call pattern (per-operation store access), a clean `SecretStore` trait, and
no metadata cache to invalidate. The rosec custom provider is a close second, but it needs a small
daemon change to be truly sync-on-read.

### 15.3 Merge caveat

True KeePassXC-style merge needs a per-item revision (timestamp + host, or a small vector) so two
diverged versions can be ordered; for opaque secrets the realistic outcomes are "newest wins" or
"both versions surfaced". That is ~1 extra day on top of the estimates above and is a product
decision, not a storage-layer one.

## 16. Running with the stock OpenSSH agent (rosec SSH feature off)

Decision context: eventual consistency (a ~1 minute window is acceptable), one agent only,
YubiKey keys handled by the stock FIDO2-capable OpenSSH agent.

- **Turn rosec's SSH feature off**: `[service] ssh_fuse = false` (`rosec-core/src/config.rs:98`,
  consumed at `rosecd/src/main.rs:174`). This disables the agent socket, the FUSE tree, the
  `config.d` snippets and the generated `allowed_signers` in one switch. No fork.
- **Keep the vault unlocked**: `[autolock]` policy plus `unlock_timeout_secs` (default 30 s;
  set a long value, e.g. 86400, or disable the idle/max lock) so the feeder can read items.
- **Feeder** (a systemd user service + timer, ~0.5–1 day including tests):
  1. `rosec search type=ssh-key` → item ids (AND-attribute filters; `type` is a common attribute
     name).
  2. For each id: `rosec get <id>` → 0600 temp file → `ssh-keygen -y -f` for the public key →
     `ssh-add -t <ttl> <temp>`; shred the temp.
  3. On each run, remove keys the feeder previously managed (`ssh-add -d <pub>`) before re-adding,
     so deleted/rotated items disappear within one interval. Keep a small state file of managed
     fingerprints.
  4. Regenerate `allowed_signers` from the fetched public keys (`<principal> <pub>`) into the file
     `gpg.ssh.allowedSignersFile` points at; truncate it when the vault is locked (fail-closed).
  5. If `rosec get` fails (provider locked), remove the managed keys — the same eventual-
     consistency window applies.
- **YubiKey keys**: store the sk key **handle** (`id_ed25519_sk`, credential handle + public key,
  no secret) as an ssh-key item; the feeder loads it into the stock agent with `ssh-add`, and
  signing still touches the YubiKey. No rosec sk-ssh support needed.
- **What is lost vs rosec's own agent**: automatic revocation on lock (replaced by the timer),
  the FUSE `config.d` host snippets (replace with a static `~/.ssh/config` or the feeder writes
  them), and the signing-confirmation policy (the stock agent has none).
- **Alternative**: keep rosec's agent and run both (rosec's for vault keys, stock for FIDO2) —
  automatic revocation for free, but two sockets and `IdentityAgent` routing.

## 17. Store shape, KeePassXC provider access, and Secret Service structure

### 17.1 Local vault shape (source: `rosec-vault/src/types.rs`)

On disk (`<id>.vault`, JSON): `version`, `wrapping_entries[]` (`id`, `label`, `kdf{salt,
iterations}`, `wrapped_vault_key`, `wrapped_key_hmac`), `encrypted_data` (base64 AES-256-CBC
payload), `hmac`. Decrypted payload (`VaultData`): `items[]`, each `VaultItemData` = `id`,
`label`, `attributes: map<string,string>` (public), `secrets: map<string,string>` (**named
secrets**, e.g. `password`, `private_key`, `totp`), `content_types: map`, `created`, `modified`.
**There are no collections in the vault** — items are flat; collections are a Secret Service-level
concept. The `.meta` sidecar holds `id`, `label`, attribute **hashes**, `secret_names`,
timestamps.

### 17.2 KeePassXC provider (source: `rosec-keepassxc-file/`)

- Kind `keepassxc-file`, options `path` (required) and `key_file` (optional); the master password
  is the unlock input. Read-only ("unlock decrypts via `keepass-rs`, but the plugin never
  writes"), path-scoped to the one file (`filesystem.allowed_files`), and it registers a watch so
  KeePassXC saves are picked up.
- **Any entry is exposed** — every group/entry in the database, recursively.
- Item ID = the entry **UUID** (hyphenated). Attributes: `username`, `uri`, `folder`
  (`Group/Subgroup` path, root omitted), `tag.N`, custom **unprotected** strings, plus
  `rosec:type`, `rosec:provider`, `rosec:keepassxc:folder`, `rosec:keepassxc:uuid`,
  `rosec:totp`, `xdg:schema`. Secrets: `password`, `notes`, `totp` (when present), custom
  **protected** strings, and `private_key` for KeeAgent SSH entries. The protected/unprotected
  flag from the KDBX is honoured. KeeAgent SSH keys and FIDO2 credentials are also surfaced
  (`list_ssh_keys`/`resolve_ssh_private_key`, FIDO2 meta).
- Type heuristic: SSH entry → `ssh-key`; password → `login`; notes → `note`; else `generic`.

### 17.3 Secret Service structure

The daemon exposes **one virtual collection** (label "default") plus the `default` and `login`
aliases; items from all providers are flattened into it with **provider-scoped D-Bus paths**
(`make_item_path(provider_id, item_id)`), and a path resolves back to `(provider, item_id)` for
reads. So "collections" are a view, not a storage concept; the provider's own grouping (KDBX
groups, vault labels) appears as attributes (`rosec:keepassxc:folder`) rather than D-Bus
collections.

### 17.4 Runtime verification (KDBX) — PASS

A throwaway KDBX (2 entries, one nested group) was created with `keepassxc-cli` and the upstream
`rosec-provider-keepassxc-file-0.0.40.wasm` was installed with its policy and minisig.

- ✅ Provider **signature verified**, kind discovered, provider initialized, KDBX opened:
  `kdbx: open complete; entry count = 2`.
- ✅ `rosec search` lists both entries: `login kpxc Login2 bob`, `login kpxc Login alice
https://example.com`.
- ✅ `secret-tool search --all rosec:provider kpxc` returns both items with the passwords
  (`secret = entry-pw-1/2`), `rosec:keepassxc:folder = Test` / `Test/Sub`,
  `rosec:keepassxc:uuid`, `username`, `uri`, `rosec:type = login`, timestamps, and
  `schema = org.freedesktop.Secret.Generic`.
- ✅ **Read-only confirmed**: provider capabilities `SsF` (sync, ssh, FIDO2 — no `W`), and
  `secret-tool store` fails with `no write-capable provider available`.
- ✅ Unlock via `AuthProviderFromPipe` (`rosec-pam-unlock`): `provider authenticated via
AuthProvider provider=kpxc`.

Environment note: the first attempts failed with
`mmap(4362076160, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE) = -1 EAGAIN` (wasmtime's
4 GB reservation). Cause: the user manager's hard `RLIMIT_MEMLOCK` is 4 MB on this host, and
rosec's `harden()` calls `mlockall(MCL_FUTURE)`, so every later mapping is charged to the locked
memory budget (the shipped unit expects `LimitMEMLOCK=infinity`, which the user manager cannot
raise past its own hard limit). The test passed with a test-only `LD_PRELOAD` shim that
neutralizes `mlockall` (the code base already has `harden_no_memlock()` for this exact reason).
The system-level fix (raise the user memlock limit) is tracked separately.
