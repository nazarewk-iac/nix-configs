---
type: How-To
description: Takes an external adopter from a stock Apple Silicon Mac to nix-darwin, then to a Rosetta-backed Linux builder, then to one built x86_64-linux derivation.
timestamp: 2026-09-11T12:00:00+02:00
authored_by: agent
---

# nix-darwin getting started, up to a multi-arch build

This runbook is for an **external adopter**. You are not this repository's creator. You own a
stock Apple Silicon Mac. You want a Linux builder on it.

At the end you build one `x86_64-linux` derivation on your Mac, near native speed, through
Rosetta 2.

Scope: zero → nix-darwin → a minimal configuration that switches → the Rosetta builder → one
multi-arch build. Nothing else. This runbook adds no desktop, no Home Manager profile and no
secrets management.

Every fact below cites a file in this repository. Read the citation when you doubt a step. A row
marked `UNVERIFIED` has no evidence here — treat it as a hint, not as a fact.

## Contents

1. [Prerequisites outside any module](#1-prerequisites-outside-any-module)
2. [Which evaluator this runbook assumes](#2-which-evaluator-this-runbook-assumes)
3. [Install nix-darwin with a minimal configuration](#3-install-nix-darwin-with-a-minimal-configuration)
4. [The bootstrap dance](#4-the-bootstrap-dance)
5. [The exit test](#5-the-exit-test)
6. [Caveats: symptom, cause, fix](#6-caveats-symptom-cause-fix)
7. [Classic traps this repository cannot confirm](#7-classic-traps-this-repository-cannot-confirm)
8. [Known gaps](#8-known-gaps)
9. [Time and disk expectations](#9-time-and-disk-expectations)

---

## 1. Prerequisites outside any module

No Nix module sets these three. You set them yourself, before step 3.

### 1.1 Rosetta 2, with the Linux runtime

The builder runs `x86_64-linux` guest binaries under Rosetta 2. Rosetta must hold the **Linux**
runtime, not the macOS one alone. Check it:

```bash
ls /Library/Apple/usr/libexec/oah | grep RosettaLinux
```

The command must print a match. `docs/multi-arch-builder.md:24-28` records this exact check.

macOS installs Rosetta 2 on demand. This repository's Darwin host already had it, so nobody here
measured a fresh install. Section 7 lists that as `UNVERIFIED`.

### 1.2 Your user in `trusted-users`

A remote builder needs a trusted user. On macOS the admin group is **`@admin`**, not `@wheel`. The
plain user group is `@staff`, not `@users`.

```nix
nix.settings.trusted-users = [ "@admin" ];
```

`hosts/anji/default.nix:59` sets exactly that line.

Add the setting **before** the first switch. Then restart the Nix daemon, or reboot.

### 1.3 A writable `/nix`

The Nix installer creates the store. This runbook does not cover that step. Follow your
installer's own instructions, then continue at section 2.

---

## 2. Which evaluator this runbook assumes

**This runbook recommends the Lix installer.** This repository runs **Lix 2.95.2** on
`aarch64-darwin` (`docs/tasks/2026-09/generalization/definition.md:41`). Every measurement here
comes from that evaluator.

You may run CppNix or Determinate Nix instead. Nothing in this runbook needs Lix. These are the
differences that matter.

| Point | Lix 2.95.2 | CppNix / Determinate Nix |
|---|---|---|
| `nix.package` in this repository | The default, through `lib.mkDefault` | A plain assignment wins over the default, so you keep your own Nix (`modules/universal/default.nix:119-131`) |
| Darwin test suite | Fails. This repository builds Lix with `doCheck = false` and `doInstallCheck = false` (`modules/universal/default.nix:124-128`) | Not applicable |
| `lazy-trees` | Absent. A source-wide search of the Lix 2.95.2 tree returns **0** hits (`docs/tasks/2026-09/generalization/010-flake-input-overhead/research.md:382`) | Determinate Nix ships it. Do not depend on it in shared code |
| A stale evaluation result | `--no-eval-cache` fixes it. Reproduced on Lix 2.95.2, `aarch64-darwin` (`docs/den-for-adopters.md:600`) | Same flag exists |
| `builtins.convertHash` | Reported absent. It broke a Homebrew-related overlay here, and the creator dropped the inputs | Present. `UNVERIFIED` — no code trace of the failure remains in this repository |

Do **not** assume Lix in your own modules. Keep `nix.package` at `lib.mkDefault` priority, so an
adopter with CppNix keeps CppNix with one plain line.

An installer conflict between the three Nix flavours is plausible. This repository never met one,
so section 7 marks it `UNVERIFIED`.

---

## 3. Install nix-darwin with a minimal configuration

Write a flake with **four** mandatory settings. nix-darwin activation fails without the first two.

```nix
{
  inputs.nix-configs.url = "github:nazarewk-iac/nix-configs";
  inputs.nixpkgs.follows = "nix-configs/nixpkgs";
  inputs.nix-darwin.follows = "nix-configs/nix-darwin";

  outputs =
    { nix-darwin, nix-configs, ... }:
    {
      darwinConfigurations.example = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          {
            system.stateVersion = 6;
            system.primaryUser = "adopter";
            users.users.adopter.home = "/Users/adopter";
            nixpkgs.hostPlatform = "aarch64-darwin";

            nix.settings.trusted-users = [ "@admin" ];
          }
        ];
      };
    };
}
```

Each line earns its place:

- `system.stateVersion = 6` — this repository's value (`hosts/anji/default.nix:45`).
- `system.primaryUser` — activation fails without it. This repository defaults it to the primary
  user's name (`modules/universal/profile/user/kdn/default.nix:527`).
- `users.users.<name>.home` — nix-darwin does not synthesize `home` for a user that macOS already
  created. See caveat B1.
- `nixpkgs.hostPlatform` — the platform of the host. See caveat B4 for the two shapes that work.

Switch it:

```bash
nix run nix-darwin -- switch --flake .#example
```

`darwin-rebuild switch` needs root. Build unprivileged first, then switch. Caveat A13 explains why.

---

## 4. The bootstrap dance

This is the part you cannot guess. It is the core of this runbook.

### 4.1 Why a dance exists

`nix-rosetta-builder` starts a Lima Linux guest. The guest image is itself an **`aarch64-linux`**
derivation. So the Rosetta builder needs a Linux builder that already exists, to build its own
guest image the first time (`docs/multi-arch-builder.md:176-178`,
`modules/slots/rosetta-builder/default.nix:8-10`).

A fresh Mac has no Linux builder. So you borrow one: the **stock** `nix.linux-builder`, whose image
comes from the public binary cache.

### 4.2 The exact order

Follow these five steps. Do not merge them.

**Step 1 — enable the stock builder, unmodified.**

```nix
nix.linux-builder.enable = true;
nix.linux-builder.ephemeral = true;   # the guest disk is wiped on every restart
```

Change nothing else about it. Read section 4.3 first.

**Step 2 — switch.**

```bash
nix run nix-darwin -- switch --flake .#example
```

Confirm the builder exists before you go on:

```bash
cat /etc/nix/machines
```

One line must name `aarch64-linux`. `docs/multi-arch-builder.md:56-58` shows the shape.

**Step 3 — add the Rosetta builder beside the stock one.** Keep the stock builder on.

Either consume this repository's **den aspect**:

```nix
modules = [
  nix-configs.denModules.rosetta-builder
  # …your own settings…
];
```

Or consume the **slot** through `mkSlots`:

```nix
modules = [
  (nix-configs.mkSlots {
    inherit pkgs;
    kdn.darwin.rosetta-builder.enable = true;
  }).config.darwin
  # …your own settings…
];
```

The aspect declares **no** `enable` option — inclusion in the module list is the switch
(`modules/den/aspects/rosetta-builder.nix:16-18`). The slot declares
`kdn.darwin.rosetta-builder.enable` instead
(`modules/slots/rosetta-builder/default.nix:70-71`).

Both routes need no packages overlay: the module reads no `pkgs.kdn.*` attribute. Both set three
opinions for you — `nix-rosetta-builder.enable = true`, `onDemand = true` (the guest powers off
when idle) and `nix.settings.builders-use-substitutes = true` (the guest pulls its own inputs from
a public cache).

`docs/slots-for-adopters.md` documents the `mkSlots` call in full. `docs/den-for-adopters.md`
documents the aspect route, with a worked nix-darwin example at lines 110-138.

**Step 4 — switch again.** The Lima guest image now builds on the stock builder.

```bash
nix run nix-darwin -- switch --flake .#example
```

Then confirm both builders:

```bash
cat /etc/nix/machines
```

You must see two lines. One names `aarch64-linux,x86_64-linux` for the Rosetta guest. One names
`aarch64-linux` for the stock builder (`docs/tasks/2026-07/multi-arch-rosetta-builder/done.md:49-51`).

The launchd service must be loaded:

```bash
sudo launchctl print system/org.nixos.rosetta-builderd | head -5
```

**Step 5 — optional: turn the stock builder off.** The Rosetta guest already registers
`aarch64-linux`, so the stock builder is now redundant. This repository keeps it on as a
known-good fallback (`docs/tasks/2026-07/multi-arch-rosetta-builder/done.md:66-68`). Do the same
until the exit test in section 5 passes twice.

### 4.3 Two traps inside the dance

**Trap 1 — do not customize the stock builder on the first switch.** A custom
`nix.linux-builder.package` or a custom `nix.linux-builder.config` is itself a Linux derivation.
On a fresh Mac nothing can build it. This repository gates every customization behind one
bootstrap toggle for exactly this reason (`hosts/anji/default.nix:11,30,60`).

**Trap 2 — two builders at once are fragile.** Both cached builder images default to
`hostPort = 31022`, and you cannot build a custom-port image until a builder already exists.
`docs/multi-arch-builder.md:197-200` records this as "a fragile, multi-step dance (often needs
`--option sandbox false`)". It cites nix-darwin#1192. So run the dance once, in order, and do not
add a third builder.

### 4.4 Phased enablement — planned, not yet available

Checkpoint 002 plans a `bootstrap` phase and a `steady` phase on the slot itself
(`docs/tasks/2026-09/generalization/002-rosetta-builder-adopter-dropin/definition.md:59-85`). The
option surface is not settled and the code does not exist yet. Until it lands, use the manual
five-step sequence above. Keep it as the fallback afterwards.

---

## 5. The exit test

Build one derivation that **must** run on an `x86_64-linux` machine. A trivial `runCommand` cannot
be substituted from a cache, so it proves the builder really ran.

```bash
nix build --no-link --print-out-paths --impure --expr \
  'with import <nixpkgs> { system = "x86_64-linux"; }; runCommand "x" {} "uname -m > $out"'
```

Then read the result:

```bash
cat "$(nix build --no-link --print-out-paths --impure --expr \
  'with import <nixpkgs> { system = "x86_64-linux"; }; runCommand "x" {} "uname -m > $out"')"
```

### What success looks like

- The build log names the builder, for example `ssh-ng://rosetta-builder`.
- `nix build` prints one store path.
- `cat` on that path prints exactly `x86_64`.

Run the `aarch64-linux` twin too, to prove the guest serves both arches:

```bash
nix build --no-link --print-out-paths --impure --expr \
  'with import <nixpkgs> { system = "aarch64-linux"; }; runCommand "a" {} "uname -m > $out"'
```

That path must hold `aarch64`. `docs/multi-arch-builder.md:327-334` is the source of both
commands.

`<nixpkgs>` reads `NIX_PATH`. A flakes-only setup may leave it empty. Then add an explicit entry:

```bash
nix build --no-link --print-out-paths --impure \
  -I nixpkgs=flake:nixpkgs --expr \
  'with import <nixpkgs> { system = "x86_64-linux"; }; runCommand "x" {} "uname -m > $out"'
```

### A stronger proof, optional

Build a real package for `x86_64-linux` and inspect an ELF header in its closure. This repository
did that: the Python interpreter in one closure was a genuine x86_64 ELF
(`e_machine = 0x3e`, `EM_X86_64`). So the builder compiles real x86_64 binaries — it does not
fetch Darwin paths from a cache
(`docs/tasks/2026-07/multi-arch-rosetta-builder/done.md:55-58`).

### When the test fails

Read section 6 first. Row A2, A3 and A4 cover the three most common failures.

---

## 6. Caveats: symptom, cause, fix

This is the most valuable section. Every row cites a file in this repository. A row marked
`UNVERIFIED` has no such evidence — the claim is recorded, but nothing here proves it.

Search the literal error text. That is what you type into a search engine.

### Table A — the builder

| # | Symptom | Cause | Fix | Evidence |
|---|---|---|---|---|
| A1 | You cannot build a customized Linux builder on a fresh Mac | Chicken and egg: the customization is itself a Linux derivation | First switch uses the stock cached builder. Gate every customization behind a toggle | `hosts/anji/default.nix:11,30,60` |
| A2 | An error about "not being on linux and that substitutes are not allowed", during a Linux `toplevel` build from Darwin | Nix refuses to substitute the outer derivation, because the local system cannot build it | Pass `--always-allow-substitutes` | `packages/darwin-rebuild/darwin-rebuild.sh:140-141` |
| A3 | `/nix/store/…-stdenv-linux/setup: line 1828: wrapProgram: command not found` | A build of a **customized** Linux builder VM from Darwin | **Unresolved here.** An open TODO sits above `nix.buildMachines`. Treat it as a known trap, not a solved one | `hosts/anji/default.nix:69` |
| A4 | `x86_64-linux` derivations still refuse to schedule after you add `"x86_64-linux"` to `systems` | A `systems` entry alone does nothing. The guest needs the emulation handler too | Use the Rosetta module, which registers both arches itself. On the QEMU route add `boot.binfmt.emulatedSystems`. Cites nix-darwin#1192 | `docs/multi-arch-builder.md:113-119` |
| A5 | Two builders fight, or the second guest never starts | Both cached builder images default to `hostPort = 31022`, and a custom-port image needs a builder that already exists | Run one dual-arch guest. Do not bootstrap two custom builders. Expect `--option sandbox false` on that path | `docs/multi-arch-builder.md:197-200` |
| A6 | A build fails, and the log holds many `deleting '/nix/store/…'` lines | The guest collects its own garbage in the middle of your build. Upstream bakes `min-free = 5G` and `max-free = 7G` into the guest | Set `guest.minFree = 0` and watch the guest disk yourself. Measured here: 622 delete lines in one pass; a manual collection freed 72.5 GiB over 9930 paths | `modules/slots/rosetta-builder/default.nix:100-113` |
| A7 | The guest loses every cached build result after a small config change | `memory`, `cores`, `diskSize`, `minFree` and `maxFree` all feed the generated `lima.yaml`. On a difference the daemon runs `limactl delete --force`, then `limactl create` | Change one of these once, on purpose. Never to chase one failed build | `modules/slots/rosetta-builder/default.nix:25-29`; `modules/den/aspects/rosetta-builder.nix:31-35` |
| A8 | The host disk fills up, and the guest reports no error | The guest disk is a **sparse** file on the host disk. An oversized guest fills the host instead of failing its own build | Keep the `guest.diskSizeMax` ceiling. Upstream's `100GiB` default was enough for a three-host build here | `modules/slots/rosetta-builder/default.nix:73-93` |
| A9 | `error: a 'i686-linux' with features {} is required to build '…', but I am a 'aarch64-darwin'` | Rosetta for Linux is **x86_64-only**. Its binfmt handler registers only the x86_64 ELF magic | Known gap. Do not add `i686-linux` to `systems` — the failure only moves from schedule time to build time | `docs/tasks/2026-08/rosetta-builder-i686-linux/definition.md:20-38` |
| A10 | The guest rejects paths your host serves as a substituter | The guest refuses unsigned or untrusted paths | `trusted-public-keys` in the guest is **mandatory**. Sign with `nix-serve`'s `secretKeyFile` | `docs/multi-arch-builder.md:255-268` |
| A11 | You add a `post-build-hook` or a manual `nix copy`, and results still look wrong | The remote-builder protocol already copies each output plus its runtime closure back to the host store | Add neither for the normal flow. A `post-build-hook` is only for an **external** cache | `docs/multi-arch-builder.md:271-273` |
| A12 | `error: unexpected end-of-file` from a `git+file://` fetch, before any build starts | A dangling `refs/remotes/<remote>/HEAD` symref. Nix's libgit2 fetcher is stricter than the git CLI | `git remote set-head <remote> <branch>` | `docs/tasks/2026-07/multi-arch-rosetta-builder/done.md:62-65` |
| A13 | `sudo nom build` leaves root-owned store paths, or breaks the builder | Only `darwin-rebuild` needs root. The build does not | Split it: build unprivileged, then `sudo darwin-rebuild …` | `packages/darwin-rebuild/darwin-rebuild.sh:142` |

### Table B — the nix-darwin host

| # | Symptom | Cause | Fix | Evidence |
|---|---|---|---|---|
| B1 | Home Manager evaluates `home = null` for a user macOS already created | nix-darwin does not synthesize `home` or `uid` for a pre-existing macOS user | Set `users.users.<name>.home` and `.uid` explicitly. This repository pins root's `home = "/var/root"` and `uid = 0` | `modules/universal/default.nix:300-301` |
| B2 | The remote builder refuses your user, and `@wheel` changes nothing | On macOS the admin group is `@admin`. `@wheel` and `@users` are Linux group names | `nix.settings.trusted-users = [ "@admin" ];` | `hosts/anji/default.nix:59` |
| B3 | Activation fails and names a missing primary user | nix-darwin needs `system.primaryUser` | Set it to your own user name | `modules/universal/profile/user/kdn/default.nix:527` |
| B4 | Host evaluation breaks on `nixpkgs.hostPlatform` plus `darwinSystem { system = …; }` | nix-darwin moved to `nixpkgs.system` | Two shapes are recorded as working. This repository passes `{ nixpkgs.system = host.system; }` into `lib.darwinSystem`. The adopter guide's example passes `system = "aarch64-darwin"` plus `nixpkgs.hostPlatform` | `flake.nix:357-361`; `docs/den-for-adopters.md:117-127` |
| B5 | `homebrew.taps` conflicts with `nix-homebrew.taps`, and an untrusted tap source blocks an install | nix-homebrew manages the `homebrew/*` taps itself | Filter taps by the `homebrew/` prefix **and** set `trusted = true`. This repository took three iterations and tracks nix-homebrew#128 | `modules/universal/default.nix:243-252` |
| B6 | Brews and casks never update on a rebuild | `homebrew.onActivation.upgrade` defaults off | `homebrew.onActivation.upgrade = true;` | `modules/universal/default.nix:230` |
| B7 | Cask URLs break after a macOS major upgrade | A cask set is per macOS release | Track the release name in the cask input. This repository pins `osVersion = "tahoe"` | `flake.nix:232` |
| B8 | A build fails with "does not support your platform", from a Linux-only Home Manager module | The tree imports a Linux-only HM module unconditionally into a Darwin host's HM child | Guard the import by parent type | `modules/universal/_stylix.nix:22-23,89-90` |
| B9 | A Home Manager launchd agent never starts after a reboot or a relogin | An HM launchd agent defaults to no `RunAtLoad`, so only activation starts it | `launchd.agents.<name>.config.RunAtLoad = true;` | `modules/universal/programs/atuin/default.nix:71,90` |
| B10 | Evaluation aborts on a Linux-only or broken package in a list you share across platforms | One package list serves both platforms | Filter `meta.broken`, `meta.unsupported`, `!meta.available` and `tryEval` failures, with a warning | `modules/universal/env/default.nix:32-50` |
| B11 | `pinentry-all` is unusable on Darwin | `pinentry-qt` builds only on Linux or `x86_64-darwin` | Use `pkgs.pinentry_mac` on Darwin | `modules/universal/programs/gnupg/default.nix:13` |
| B12 | A FIDO2 `sk-ssh-ed25519` YubiKey key does not work with ssh | Apple's built-in ssh-agent holds no libfido2 | Run OpenSSH's own agent, and claim `SSH_AUTH_SOCK` through launchd. **Skip root**: root has no GUI login session, so the `gui/0` bootstrap fails with error 125 | `modules/slots/ssh-agent/default.nix:16,39-41` |
| B13 | `devenv update` breaks while a git `insteadOf` HTTPS→SSH rewrite is in place | The Nix and devenv fetchers hit the rewritten URL | Clear that URL override. Use a credential helper instead. This repository rewrites the other way, SSH→HTTPS, and pairs it with a credential helper | `modules/universal/profile/user/kdn/default.nix:274-279` |
| B14 | `nix flake lock --reference-lock-file` rejects a temporary path | macOS `/tmp` is a symlink to `/private/tmp`, and Nix validates the real path | Resolve the directory with `os.path.realpath` | `packages/flake-lock-merge/flake_lock_merge/cli.py:38` |
| B15 | The Lix build fails its own test suite on Darwin | The Lix test suite fails on Darwin | Override with `doCheck = false` and `doInstallCheck = false` | `modules/universal/default.nix:124-128` |
| B16 | An evaluation returns a stale result after you change a file | The flake evaluation cache | Pass `--no-eval-cache`. Reproduced on Lix 2.95.2, `aarch64-darwin` | `docs/den-for-adopters.md:600` |
| B17 | `users.users.<name>.username` does not exist | `.name` is the shared NixOS and Darwin option | Use `.name` | `UNVERIFIED` — recorded in `docs/tasks/2026-09/generalization/003-nix-darwin-getting-started/definition.md:79`, no code trace |
| B18 | The login shell has no effect | nix-darwin does not set the login shell from `programs.fish` | Set `users.users.<name>.shell` | `UNVERIFIED` — recorded in the same task definition, line 92, no code trace |
| B19 | `stdenv.isDarwin` prints a deprecation warning | nixpkgs moved to `stdenv.hostPlatform.*` | Use `stdenv.hostPlatform.isDarwin` | `UNVERIFIED` — a repository-wide search returns 0 uses of the old attribute, so nothing here reproduces the warning |
| B20 | An overlay breaks on a missing `builtins.convertHash` | Lix reportedly lacks that builtin. It broke a Homebrew-related overlay here | Drop the overlay, or move to a Nix that has the builtin | `UNVERIFIED` — recorded in the same task definition, line 29; the inputs were dropped, so no code trace remains |

Row count: **33**. Rows marked `UNVERIFIED`: **4** (B17, B18, B19, B20).

---

## 7. Classic traps this repository cannot confirm

These are well-known nix-darwin traps. **This repository holds no evidence for any of them.** They
are here so you recognise them, not because they are measured. Verify each one yourself before you
act on it.

- `UNVERIFIED` — "already exists" backup-file errors on `/etc/nix/nix.conf`, `/etc/bashrc` or
  `/etc/zshrc`.
- `UNVERIFIED` — the literal `cannot add path … untrusted` error text.
- `UNVERIFIED` — an installer conflict between Determinate Nix, upstream Nix and Lix.
- `UNVERIFIED` — a need to install Rosetta 2 by hand. It was already present here.
- `UNVERIFIED` — SIP problems, `/nix` volume creation, or a macOS major upgrade that wipes
  `/etc/synthetic.conf` or the Nix volume. This repository's Darwin host survived a macOS major
  upgrade with no recorded volume damage.
- `UNVERIFIED` — Xcode command line tools or `xcrun` problems.
- `UNVERIFIED` — Home Manager `useGlobalPkgs` backup collisions. This repository set
  `backupFileExtension` on day one as prevention, and recorded no collision
  (`modules/universal/default.nix:93`).
- `UNVERIFIED` — that `sudo` with TouchID survives a rebuild. This repository configures it, and
  nobody recorded a failure. So the claim is generic, not measured.

---

## 8. Known gaps

**`i686-linux` does not work.** Rosetta for Linux is x86_64-only. Any 32-bit derivation fails. Full
analysis: `docs/tasks/2026-08/rosetta-builder-i686-linux/definition.md`. Three directions exist
there; none is implemented. Do not advertise `i686-linux` in `nix.buildMachines[].systems` — that
only moves the failure from schedule time to build time.

**A multi-arch container image index is your own job.** The builder produces per-arch outputs. It
does not assemble the image index. `docs/multi-arch-container-builder.md` presents the approaches.

**Nested virtualization is impossible.** You cannot run this builder inside a macOS guest. Apple
exposes `isNestedVirtualizationEnabled` on the Linux-guest platform class only, so a macOS guest
starts no virtual machine of its own
(`docs/tasks/2026-09/generalization/002-rosetta-builder-adopter-dropin/definition.md:117-131`).
Run the builder on bare metal.

---

## 9. Time and disk expectations

Measured here, on one `aarch64-darwin` host:

| Work | Result | Evidence |
|---|---|---|
| A full `darwin-system` build through the bootstrap dance | 151 builds, about **21 minutes** | `docs/tasks/2026-07/multi-arch-rosetta-builder/done.md:40-42` |
| A three-host build on a 99 G guest disk | Guest free space fell to 19.1 GB. Upstream's `100GiB` default held | `modules/slots/rosetta-builder/default.nix:84-88` |
| One manual guest garbage collection | Freed 72.5 GiB over 9930 paths, and took free space from 19.1 GB to 96.0 GB | `modules/slots/rosetta-builder/default.nix:107-110` |

`UNVERIFIED` — a full NixOS `toplevel` at about 22 minutes warm, about 32 minutes warm on a real
Linux desktop, and about 6 hours cold. These three figures appear in the task definition, and no
measurement record here supports them.

Two settings pay for themselves:

- `nix.settings.builders-use-substitutes = true` — the guest pulls its own build inputs from a
  public cache, instead of the host uploading everything over the slow guest link. Both the slot
  and the aspect set it for you (`modules/slots/rosetta-builder/default.nix:150`).
- `nix-rosetta-builder.onDemand = true` — the guest powers off when it is idle. Both set it
  (`modules/slots/rosetta-builder/default.nix:147`).
