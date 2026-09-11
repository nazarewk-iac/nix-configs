---
type: Research
title: Darwin VM testing — the 2026-09-11 re-check
description: What changed in the repository after the three 2026-09-09 research files, plus a fresh licence and subcommand check of tart.
task: definition.md
authored_by: agent
timestamp: 2026-09-11T00:00:00+02:00
---

# Darwin VM testing — the 2026-09-11 re-check

Owning task: [definition.md](definition.md). Design: [design.md](design.md).

Three research files date from 2026-09-09 and 2026-09-10:
[tart.research.md](tart.research.md), [lume.research.md](lume.research.md) and
[repo-surface.research.md](repo-surface.research.md). This file records only what changed after
them, plus the claims I re-checked at a primary source.

Every claim carries a state. `verified` names the source. `UNVERIFIED` marks a guess or an
absence of evidence.

## What changed in the repository

### 1. Five Darwin checks now exist

`repo-surface.research.md` states that `checks/` holds four checks and no Darwin check. That is
now **stale**. The repository holds 57 checks plus 6 bundles (`checks/README.md`), and five of
them read a Darwin artifact.

| Check | Site | What it proves |
|---|---|---|
| `den-artifact-host-darwin` | `checks/den-mvp/tests.nix:3502-3517` | three `nix.conf` settings; `devenv` on the system path; the launchd plist file exists; the `activate` **text** names the daemon |
| `den-artifact-hm-host-darwin` | `tests.nix:3522-3524` | the home-manager generation of the `dev` user |
| `den-artifact-home-darwin` | `tests.nix:3525-3527` | the same half, standalone |
| `den-smoke-devenv-darwin` | `tests.nix:3529` | devenv's `config.test` runs |
| `den-smoke-host-darwin` | `tests.nix:3530` | the same, for the derived host shell |

State: `verified` by reading the file.

**None of them activates anything.** `checks/den-mvp/tests.nix:1` states it: "Three tiers, and no
tier activates anything." `tests.nix:14-15` states it again: "Tier 2 reads a built store path and
never executes it."

### 2. A depersonalized Darwin subject now exists

`flake.denConfigurations.host-darwin` is a real nix-darwin system with one user, `dev`. State:
`verified` at `modules/den/flake-module.nix:168-169` and
`checks/den-mvp/host-darwin/default.nix:1-24`.

This retires four blockers of `repo-surface.research.md`, because all four assume the subject is
the creator's own host:

| Blocker | State now |
|---|---|
| H2 the creator's macOS account | not applicable — the den host has one user, `dev` |
| H3 sops decryption at activation | not applicable — the den host reads no sops file |
| H4 `stylix.image` from a personal host | not applicable — the den host loads no stylix module |

### 3. The Homebrew tap scan is now opt-in

`repo-surface.research.md` blocker H1 says a Darwin host build forces every `brew-tap--*` flake
input, so a keyless guest stops there. That is now **resolved for a public build**.

`modules/universal/default.nix:262-291` makes the scan opt-in:
`nix-homebrew.taps = lib.mkIf cfg.homebrew.tapsFromFlakeInputs (...)`. The comment at `:266-267`
states the default: "`kdn.homebrew.tapsFromFlakeInputs` defaults to `false`, and each darwin host
of this repository sets it to `true` in its own file."

State: `verified` by reading the file. A den subject sets the option nowhere, so it takes the
`false` default and forces no tap input.

## What I re-checked at a primary source

### tart licence — unchanged and clean

I read tart's `LICENSE` on `main` this session. State: `verified`.

| Fact | Value |
|---|---|
| Identifier | `FSL-1.1-ALv2` |
| Copyright | `Copyright 2022-2026 OpenAI` |
| Permitted Purpose | "A Permitted Purpose is any purpose other than a Competing Use." |
| Competing Use | a commercial product or service that substitutes for the software, substitutes for another product the licensor offers with it, or offers substantially similar functionality |
| Employee-count threshold | **none** |
| Revenue threshold | **none** |
| Future licence | Apache-2.0, on the second anniversary of each release |

So internal use on a company-owned laptop is a Permitted Purpose. This agrees with
`tart.research.md:31`, and it adds a fresh reading of the same file.

The nixpkgs `tart` package stays unusable: `definition.md:76-77` records it stale at 2.30.6 and
still `unfree` with `license.shortName = "fairsource09"`. So tart comes from Homebrew.

### tart subcommands — `exec` needs no SSH, `suspend` needs macOS 14

I read `Sources/tart/Root.swift` on `main` this session. State: `verified`.

The registered subcommands, in order: `Create`, `Clone`, `Run`, `Set`, `Get`, `List`, `Login`,
`Logout`, `IP`, `Exec`, `Pull`, `Push`, `Import`, `Export`, `Prune`, `Rename`, `Stop`, `Delete`,
`FQN`, `Suspend`.

Two readings matter for the design:

- **`Exec` is present with no platform condition.** So a harness runs a guest command with no
  `ssh`. That removes `definition.md` blocker 14 from every step except the closure copy.
- **`Suspend` is present only behind `#available(macOS 14, *)`.** So a warm-restore loop is
  possible on this host, but it stays unmeasured.

### The base image size — the doc understates it

tart's own README says the quick start "will download a 25 GB image". State: `verified` by
reading it this session.

`tart.research.md:163-165` measures the real numbers: **27.31 GB compressed** over 96 layers,
and `org.cirruslabs.tart.uncompressed-disk-size` = `50000000000`, so a **50 GB** guest disk. Use
the measured numbers, not the README.

## What stays UNVERIFIED

Each row below blocks no decision, but a plan must not present any of them as a measurement.

| Claim | Why it matters |
|---|---|
| The wall clock of a `tart clone` | The whole warm-loop budget rests on "copy-on-write is near free" |
| The wall clock of a `tart` cold boot to an answered `tart exec` | lume measured 10 s and 11 s. The tart number is absent |
| Whether a Nix-built `ssh` reaches a **tart** guest on macOS 26 | Proved broken for a **lume** guest. `nix copy` is the only step that needs `ssh` |
| Whether the base image gives the guest user passwordless `sudo` | Every activation step needs guest root |
| Whether the base image runs `sshd` by default | `nix copy` needs it |
| The exact argument shape of `tart exec` and the output shape of `tart list` | Two helper functions of the harness depend on both |
| The closure size of `denConfigurations.host-darwin` | It sets the guest disk size and the copy time |
| Whether `activate` still exits 0 when `org.nixos.rosetta-builderd` cannot start | It decides whether the subject needs a variant without `kdn.rosetta-builder` |
| The `bake` wall clock | `definition.md:152` gives "about 40 minutes" as an estimate, not a measurement |
| The `run` wall clock | `definition.md:154` gives 2 to 5 minutes as an estimate. The design widens it to 5 to 15 |
