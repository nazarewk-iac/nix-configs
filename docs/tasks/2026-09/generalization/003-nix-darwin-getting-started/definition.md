---
type: Task
description: Write a nix-darwin getting-started runbook that takes an adopter from zero to a multi-arch build, with a caveats table built from this repo's own verified history.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 003 — nix-darwin getting-started runbook

Hub: [../generalization-plan.md](../definition.md). Depends on
[002](../002-rosetta-builder-adopter-dropin/definition.md). Last of the first commit chain. Do not
push.

Goal: `docs/nix-darwin-getting-started.md`, `type: How-To`. An adopter with a stock Mac reaches a
working `x86_64-linux` build by following it.

## Scope

Zero → nix-darwin installed → a minimal configuration that switches → the Rosetta builder running
→ one multi-arch build. Nothing else.

State which evaluator the runbook assumes. **Recommend the Lix installer.** Note that the adopter
may be on CppNix or Determinate Nix instead, and name where behaviour differs. Two Lix-on-Darwin
facts, both verified in this repo, belong in that note:

- Lix's test suite fails on Darwin, so this repo builds Lix with `doCheck = false` and
  `doInstallCheck = false` (`modules/universal/default.nix:97-104`).
- Lix lacks `builtins.convertHash`. That broke a Homebrew-related overlay here until the inputs
  were dropped. An adopter using such an overlay needs to know.

## The bootstrap dance — the core of the runbook

This is the part an adopter cannot guess. It is verified twice over.

`nix-rosetta-builder` needs an existing Linux builder to build its own Lima guest image the first
time, because that image is an `aarch64-linux` derivation. So the order is:

1. Enable **stock** `nix.linux-builder`, unmodified. It must come from the binary cache.
2. Switch.
3. Enable the Rosetta builder alongside it. The Lima guest image now builds on the stock builder.
4. Switch again.
5. Optionally turn the stock builder off.

Two traps inside this:

- **Do not customize the stock builder on the first switch.** A customized
  `nix.linux-builder.package` or `.config` is itself a Linux derivation, so there is nothing to
  build it with. This repo gates all customization behind a bootstrap toggle for exactly this
  reason (`hosts/anji/default.nix`).
- **Running two builders at once is fragile.** Both cached builder images default to
  `hostPort = 31022`, and a custom-port image cannot be built until a builder already exists.
  `docs/multi-arch-builder.md` records this verbatim as "a fragile, multi-step dance (often needs
  `--option sandbox false`)", citing nix-darwin#1192.

Checkpoint 002 adds phased enablement to the slot. Once that exists, the runbook should point at
the phases rather than describe manual steps. Keep the manual sequence as the fallback.

## Prerequisites to state

- Rosetta 2 installed, including the Linux runtime. Check that
  `/Library/Apple/usr/libexec/oah` contains `RosettaLinux`.
- The user in `trusted-users`. On macOS the admin group is **`@admin`**, not `@wheel`, and the user
  group is `@staff`, not `@users`. This repo sets `nix.settings.trusted-users = [ "@admin" ]`.
- `system.primaryUser` must be set. nix-darwin activation fails without it.
- `system.stateVersion` — this repo uses 6.

## The caveats table — verified in this repo's history

Present these as symptom → cause → fix. Every row below has evidence in this repo. Include the
literal error text where it exists, because that is what an adopter searches for.

| Symptom | Cause | Fix |
|---|---|---|
| The customized Linux builder cannot be built on a fresh Mac | Chicken-and-egg: the customization is itself a Linux derivation | First switch uses the stock cached builder; gate customization behind a toggle (`hosts/anji/default.nix`) |
| Error about "not being on linux and that substitutes are not allowed" when building a Linux `toplevel` from Darwin | Nix refuses to substitute the outer derivation because the local system cannot build it | Pass `--always-allow-substitutes` (`packages/darwin-rebuild/darwin-rebuild.sh`) |
| `/nix/store/…-stdenv-linux/setup: line 1828: wrapProgram: command not found` | Building the customized Linux builder VM from Darwin | **Unresolved** in this repo — a standing TODO above `nix.buildMachines` in `hosts/anji/default.nix`. Present it as a known trap, not a solved one |
| Home Manager evaluates `home = null` for a pre-existing macOS user | nix-darwin does not synthesize `home`/`uid` for users macOS already created | Set `users.users.<name>.home` and `.uid` explicitly (this repo pins root's `home = "/var/root"` and `uid = 0`) |
| `users.users.<k>.username` does not exist | `.name` is the shared NixOS/Darwin option | Use `.name` |
| Host eval breaks on `nixpkgs.hostPlatform` plus `darwinSystem { system = …; }` | nix-darwin moved to `nixpkgs.system` with `system = null` | `flake.nix:328-336` shows the working shape |
| `homebrew.taps` conflicts with `nix-homebrew.taps`; untrusted tap sources block installs | nix-homebrew manages `homebrew/*` taps itself | Filter taps by the `homebrew/` prefix **and** `trusted = true`. Took this repo three iterations, tracking nix-homebrew#128 |
| Brews and casks never update on rebuild | `homebrew.onActivation.upgrade` defaults off | Set it true |
| Cask URLs break after a macOS major upgrade | Cask sets are per-macOS-release | Track the release name in the cask input (`flake.nix:207`) |
| Build fails with "does not support your platform" from a Linux-only Home Manager module | A Linux-only HM module is imported unconditionally into a Darwin host's HM child | Guard it by parent type (`modules/universal/_stylix.nix`) |
| A Home Manager launchd agent never starts after reboot or relogin | HM launchd agents default to no `RunAtLoad`, so only activation starts them | Set `RunAtLoad = true` (`modules/universal/programs/atuin/default.nix`) |
| Eval aborts on Linux-only or broken packages in a shared package list | One package list is shared across platforms | This repo filters `meta.broken`, `meta.unsupported`, `!meta.available`, and `tryEval` failures with a warning, in `modules/universal/env/default.nix` |
| `pinentry-all` unusable | Needs `pinentry_mac`; `pinentry-qt` builds only on Linux or x86_64-darwin | See `modules/universal/programs/gnupg/default.nix` |
| A FIDO2 `sk-ssh-ed25519` YubiKey key does not work with ssh | Apple's built-in ssh-agent has no libfido2 | Run OpenSSH's own agent and claim `SSH_AUTH_SOCK` via launchd (`modules/slots/ssh-agent/default.nix`). Skip root — root has no GUI login session, so the `gui/0` bootstrap fails with error 125 |
| `devenv update` breaks with a git `insteadOf` HTTPS→SSH rewrite in place | Nix and devenv fetchers hit the rewritten URL | Clear the URL overrides; use a credential helper instead |
| `nix flake lock --reference-lock-file` rejects a temp path | macOS `/tmp` is a symlink to `/private/tmp` and Nix validates the real path | Resolve with `os.path.realpath` (`packages/flake-lock-merge/flake_lock_merge/cli.py`) |
| `sudo nom build` leaves root-owned store paths or breaks the builder | Only `darwin-rebuild` needs root, not the build | Split it: build unprivileged, then `sudo darwin-rebuild …` |
| The login shell is not applied | nix-darwin does not set it from `programs.fish` | Set `users.users.<name>.shell` |
| `error: a 'i686-linux' … is required to build …, but I am a 'aarch64-darwin'` | Rosetta for Linux is x86_64-only. Advertising `i686-linux` only moves the failure from schedule time to build time | Known gap — [rosetta-builder-i686-linux.md](../../../rosetta-builder-i686-linux.md) |
| `error: unexpected end-of-file` from a `git+file://` fetch | A dangling `refs/remotes/<remote>/HEAD` symref | `git remote set-head <remote> <branch>` |
| `stdenv.isDarwin` deprecation warnings | nixpkgs moved to `stdenv.hostPlatform.*` | Use the new attribute |

Two more facts worth stating, both from `docs/multi-arch-builder.md`:

- Adding `"x86_64-linux"` to `systems` **without** the binfmt line does nothing (nix-darwin#1192).
- On the guest substituter, `trusted-public-keys` is mandatory — the guest refuses unsigned paths.
  And do **not** add a `post-build-hook` or a manual `nix copy` for the normal flow.

Set expectations on time. A full NixOS `toplevel` built through the Rosetta builder took about
**22 minutes warm** here, against about **32 minutes warm** on a real Linux desktop and about
**6 hours cold**.

## Do not present these as verified

These are classic nix-darwin traps with **no evidence in this repo's history**. Either verify each
one independently before it goes in, or mark it clearly as unverified:

- `/etc/nix/nix.conf`, `/etc/bashrc`, `/etc/zshrc` "already exists" backup-file errors.
- The literal `cannot add path … untrusted` error text.
- A Determinate Nix versus upstream Nix versus Lix installer conflict.
- Rosetta 2 needing installation — here it was already present.
- SIP, `/nix` volume creation, or a macOS upgrade wiping `/etc/synthetic.conf` or the nix volume.
  This repo's Darwin host survived a macOS major upgrade with no recorded volume damage.
- Xcode command line tools or `xcrun` problems.
- Home Manager `useGlobalPkgs` backup collisions. This repo set `backupFileExtension` on day one as
  prevention and never recorded a collision.
- That sudo with TouchID survives a rebuild. It is configured here, but no failure was ever
  recorded, so the claim is generic.

## Exit criteria

- A reader who follows only the runbook, on a stock Mac, reaches a built `x86_64-linux`
  derivation.
- Every caveats row is either evidenced in this repo or marked unverified.
- No fork-only path appears — see the writing constraint in the hub.
