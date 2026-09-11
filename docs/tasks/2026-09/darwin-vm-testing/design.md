---
type: Design
title: Darwin VM activation test — design and verdict
description: A hand-run flake app boots an ephemeral macOS guest with tart and activates denConfigurations.host-darwin; bundle-vm can never hold this test.
status: proposed
authored_by: agent
timestamp: 2026-09-11T00:00:00+02:00
---

# Darwin VM activation test — design and verdict

## 0. Prior work — this task already exists

`docs/tasks/2026-09/darwin-vm-testing/` is already a task directory. It holds four files:

| File | Size | Date |
|---|---|---|
| `definition.md` | 24485 B | 2026-09-09 |
| `tart.research.md` | 52945 B | 2026-09-09 |
| `lume.research.md` | 16523 B | 2026-09-10 |
| `repo-surface.research.md` | 32058 B | 2026-09-09 |

So this design adds no new research area. It settles the three open decisions of
`definition.md:67-77`, and it records what changed in the repository after 2026-09-09.

Two parts of the prior research are now **stale**, and the stale parts change the design:

1. `repo-surface.research.md` states that `checks/` holds four checks and no Darwin check. The
   repository now holds 57 checks plus 6 bundles (`checks/README.md`), and five of them are
   Darwin checks.
2. `repo-surface.research.md` blockers H1, H2, H3 and H4 all assume the subject is `hosts/anji`,
   the creator's own host. A depersonalized subject now exists, so all four blockers fall away.
   Section 2 states this.

## 1. The gap, with evidence

Every Darwin check evaluates or builds. None boots a machine, and none activates a
configuration.

| Check | Tier | What it proves | Evidence |
|---|---|---|---|
| `den-artifact-host-darwin` | artifact | `nix.conf` holds three settings; `devenv` is on the system path; the launchd plist file exists; the `activate` **text** names the daemon | `checks/den-mvp/tests.nix:3502-3517` |
| `den-artifact-hm-host-darwin` | artifact | the home-manager generation of the `dev` user holds the hook and launchd greps | `tests.nix:3522-3524` |
| `den-artifact-home-darwin` | artifact | the same half as a standalone home-manager configuration | `tests.nix:3525-3527` |
| `den-smoke-devenv-darwin` | smoke | devenv's `config.test` runs in the sandbox | `tests.nix:3529` |
| `den-smoke-host-darwin` | smoke | the same, for the shell that `den.policies.host-to-devenv` derives | `tests.nix:3530` |

The header of `checks/den-mvp/tests.nix` states the boundary itself:

- `tests.nix:1` — "Three tiers, and no tier activates anything."
- `tests.nix:14-15` — "**No tier runs during activation.** Tier 2 reads a built store path and never
  executes it."
- `tests.nix:21` — "No darwin VM framework exists at all."
- `checks/den-mvp/README.md:198-202` — the same statement, in the "Not covered yet" list.

So the exact gap is this: a Darwin configuration can evaluate, build, and pass all five checks,
and still fail `darwin-rebuild switch`. Three failure classes escape every current check:

1. **The `/etc` takeover.** nix-darwin renames `/etc/bashrc`, `/etc/zshrc`, `/etc/zshenv` and
   `/etc/zprofile` to `*.before-nix-darwin` on the **first** activation only. The creator's host
   already holds those backup files, so it can never test the first-time path again.
   `repo-surface.research.md` records this as unverified caveat `:111`.
2. **An activation script that runs.** Tier 2 greps the **text** of `$target/activate`. It never
   runs it. A script that names a daemon and still exits non-zero passes tier 2.
3. **launchd bootstrap.** A plist file that exists is not a daemon that loads.

## 2. The subject: `denConfigurations.host-darwin`, not a personal host

This is the largest change since the prior research. `flake.denConfigurations.host-darwin` is a
real nix-darwin system, and it is **depersonalized by construction**:

- `modules/den/flake-module.nix:168-169` exports it.
- `checks/den-mvp/host-darwin/default.nix:1` calls it "A build-only nix-darwin host. It never
  activates."
- Its only user is `dev` (`host-darwin/default.nix:20-24`). It reads no sops file, no
  `stylix.image`, and no `/Users/<creator>` path.
- `checks/den-mvp/host-darwin/default.nix:11` passes `system = null` to keep the evaluation pure.

So the four hard blockers of `repo-surface.research.md` no longer apply to the VM subject:

| Prior blocker | State now | Why |
|---|---|---|
| H1 `git+ssh://` tap input | **resolved for a public build** | `modules/universal/default.nix:262-291` makes the tap scan opt-in. `kdn.homebrew.tapsFromFlakeInputs` defaults to `false`, and each Darwin host of this repository sets it per host. A den subject sets it nowhere. |
| H2 the creator's macOS account | **not applicable** | The den host has one user, `dev`. |
| H3 sops decryption | **not applicable** | The den host reads no sops file. |
| H4 `stylix.image` | **not applicable** | The den host loads no stylix module. |

One aspect of the subject **cannot work in a guest**. `host-darwin` includes
`kdn.rosetta-builder` (`host-darwin/default.nix:29`). That aspect drives a Lima Linux guest, and
`definition.md` blocker 13 shows a macOS guest cannot run a nested virtual machine. It confirms
this from inside a guest: `kern.hv_support: 0`. So the `org.nixos.rosetta-builderd` daemon cannot
start in the guest. Version 1 asserts nothing about that daemon, and it records the daemon as a
known-failed unit.

**UNVERIFIED:** whether the failed daemon also makes `activate` exit non-zero. nix-darwin
bootstraps a launchd daemon during activation. A daemon that exits non-zero normally leaves
activation at exit 0, but nobody measured it here. Section 8 holds the fallback.

## 3. The VM mechanism — tart

**Choice: `tart`, version 2.33.0 or later, from Homebrew.**

One sentence: tart is the only candidate that publishes a ready macOS image past Setup
Assistant, clones it for free with APFS copy-on-write, and runs a guest command with no SSH.

### Licence position of every candidate

| Candidate | Licence | Verified how | Verdict |
|---|---|---|---|
| **tart** | **FSL-1.1-ALv2**, `Copyright 2022-2026 OpenAI` | I read `Sources`-adjacent `LICENSE` on `main` this session. "A Permitted Purpose is any purpose other than a Competing Use." A Competing Use is a commercial product that substitutes for the software. **No employee-count and no revenue threshold.** Each release turns Apache-2.0 two years after its release date. | **accepted** |
| lume | MIT (per the prior research tag; `lume.research.md` states **no** licence identifier) | UNVERIFIED here | rejected for version 1 |
| Lima | Apache-2.0 | `definition.md:91`, not re-checked here | rejected for version 1 |
| UTM | Apache-2.0, but the App Store build is paid | UNVERIFIED here | rejected |
| plain `Virtualization.framework` | Apple SDK terms | n/a | rejected |

So the licence forbids nothing this repository needs. The repository must **not** use the
nixpkgs `tart` package: `definition.md:76-77` records it as stale at 2.30.6 and still marked
`unfree` with `license.shortName = "fairsource09"`.

### Which candidates need `sudo`

**None of them needs host `sudo`**, and that is a real finding, not an assumption.
Apple's Virtualization.framework runs unprivileged under the
`com.apple.security.virtualization` entitlement. `lume.research.md` proves it by measurement: a
whole macOS guest build ran with no host `sudo`, and two follow-up experiments were **abandoned
precisely because** they needed root.

So no candidate is rejected for `sudo`. The design still needs `sudo` **inside** the guest,
because nix-darwin activation needs root. That is a throwaway guest, and
`definition.md:128` records it as permitted. `lume.research.md` proves guest `sudo` works.

### Why tart beats lume, Lima and UTM for version 1

| Need | tart | lume | Lima | UTM |
|---|---|---|---|---|
| Image past Setup Assistant | **yes**, `ghcr.io/cirruslabs/macos-tahoe-base` | no — it installs from an IPSW | no | no |
| Guest command with no SSH | **yes**, `tart exec` | no | no | no |
| Copy-on-write clone | **yes**, `tart clone` | yes | weak | no |
| Suspend and restore | **yes**, macOS 14 and later | no | no | no |
| Known blocking defect | none recorded | three: #1440, #1513, #1514 | least measured | not measured |

I verified the tart subcommand list on `main` this session. `Exec` is present with **no**
platform condition. `Suspend` is present behind `#available(macOS 14, *)`. Both matter:

- **`tart exec` removes blocker 14.** `definition.md:232-242` records that a Nix-built `ssh`
  cannot reach a lume guest on macOS 26, while `/usr/bin/ssh` can. `tart exec` runs a command over
  a guest agent, so every assertion of version 1 needs no `ssh` at all.
- **lume's defects are disqualifying for a harness.** `lume ssh` drops piped stdin and **exits 0**
  (#1514), and it corrupts binary stdout (#1513). A silent corruption at exit 0 is the worst
  failure mode a test harness can carry.

lume keeps exactly one job that tart cannot do: the hour-zero Setup Assistant path. That is a
later version, not version 1.

## 4. What the test proves — ranked

**Version 1 proves one thing: the configuration activates without an error, on a machine that
never activated one before.** Nothing else. That single claim is the whole gap of section 1.

Version 1 assertions, in order of value:

| # | Assertion | Which failure class it catches |
|---|---|---|
| A1 | `activate` exits 0 | class 2 — a script that runs, not a script that greps |
| A2 | `/run/current-system` resolves to the expected `toplevel` store path | the activation really took effect |
| A3 | `/etc/zshrc.before-nix-darwin` exists | class 1 — the first-time `/etc` takeover |
| A4 | `/etc/zshrc` names the nix-darwin marker | class 1 — the takeover wrote the new file |
| A5 | A second `activate` of the same `toplevel` exits 0 | convergence; it costs seconds |

A5 is nearly free, so version 1 keeps it.

Later versions add, in this order:

| Version | Adds | Cost |
|---|---|---|
| 2 | launchd bootstrap health per daemon, minus `org.nixos.rosetta-builderd` | small |
| 2 | live reads of `/etc/nix/nix.conf`, so the `den-artifact-host-darwin` greps become live facts | small |
| 3 | a guest reboot, then A2 again — activation that survives a boot | one boot |
| 3 | home-manager activation for the `dev` user | small |
| 4 | the hour-zero path, from an IPSW, with lume | 14 min plus, and three open defects |
| 4 | `system.defaults` read back with `defaults read` | small |
| 5 | Homebrew and the tap set; Rosetta 2 in the guest | network, minutes |

Out of scope permanently: `nix-rosetta-builder`, TouchID `sudo`, YubiKey, FileVault. `definition.md:137-140`
records each one, and blocker 13 makes the first one permanent.

## 5. The image problem

| Question | Answer | State |
|---|---|---|
| Where does the image come from? | `ghcr.io/cirruslabs/macos-tahoe-base:latest`, an OCI registry image built by `cirruslabs/macos-image-templates` | verified in `tart.research.md:159-168` |
| How large? | **27.31 GB compressed**, 96 layers. The uncompressed disk is **50 GB** (`org.cirruslabs.tart.uncompressed-disk-size` = `50000000000`) | verified in `tart.research.md:163-165` |
| Does tart's own doc agree? | No. The tart README says "25 GB image". `tart.research.md:165` calls that an understatement. I re-read the README this session and confirmed the "25 GB" wording | verified |
| Who licenses the contents? | Apple. The build templates are MIT, but each image holds a full macOS install, so Apple's SLA governs | verified in `tart.research.md:167-171` |
| How many guests per host? | **Two.** The macOS Tahoe 26 SLA grants "up to two (2) additional copies or instances". It is per host, not per person | verified in `tart.research.md:174-196` from the Apple SLA PDF |
| Is the cap only a licence cap? | No. `tart.research.md:214` records a framework limit too: more than two concurrent macOS guests is not possible | verified |

Two consequences the design must obey:

1. **Test parallelism is at most two guests.** One guest is enough for version 1.
2. **The disk cost is real.** The base image is 27.31 GB, and the guest disk grows to hold a Nix
   store. Version 1 sets the clone disk to 120 GB, and a Nix closure fills a large part of it.

The design must NOT bake the image into a Nix derivation. A 27.31 GB fixed-output derivation is
not worth its cost, and the Nix sandbox cannot run the guest anyway.

## 6. The bootstrap problem

The guest needs Nix before nix-darwin can activate. The design pays that cost **once**, into a
golden image, exactly as `definition.md:29-33` asks. Then each run clones the golden image.

### Phase `bake` — one time

| Step | Command shape | Time | State |
|---|---|---|---|
| B1 | `tart clone ghcr.io/cirruslabs/macos-tahoe-base:latest kdn-vmtest-base` | link-bound, 27.31 GB down | size verified; wall clock UNVERIFIED |
| B2 | `tart clone kdn-vmtest-base kdn-vmtest-golden` | seconds | UNVERIFIED. APFS `clonefile` gives copy-on-write, so it should be near free. `tart.research.md:534` verifies the copy-on-write claim, not the wall clock |
| B3 | `tart set kdn-vmtest-golden --disk-size 120` | seconds | UNVERIFIED |
| B4 | `tart run --no-graphics kdn-vmtest-golden &`, then poll `tart exec … true` | seconds | UNVERIFIED for tart. lume measured **10 s and 11 s** cold boot to an answered command, twice (`definition.md:153`). Treat 60 s as the budget |
| B5 | Poll `df -k /` until the APFS container grows | seconds to a minute | UNVERIFIED. `definition.md:276-277` warns: never poll `diskutil`, because it queues on `diskmanagementd` and deadlocks against the guest agent |
| B6 | Install Lix in the guest, with the `--daemon` installer | minutes | UNVERIFIED |
| B7 | Add `trusted-users` and the two experimental features to `/etc/nix/nix.conf` | seconds | — |
| B8 | Rename `/etc/{bashrc,zshrc,zshenv,zprofile}` to `*.before-nix-darwin`; move the image's own `~/.zprofile` and the `~/.profile` symlink aside | seconds | — |
| B9 | `tart stop kdn-vmtest-golden` | seconds | — |

**Total `bake` estimate: 40 to 60 minutes, dominated by B1.** `definition.md:152` gives "about 40
minutes" for the Nix install plus the first activation, and marks it an estimate, not a
measurement. I keep that mark.

Two notes on B6 and B8.

- **Use the Lix installer, not Determinate.** This repository runs Lix 2.95.2
  (`docs/nix-darwin-getting-started.md:77`). nix-darwin **aborts** activation when it detects
  Determinate: `error: Determinate detected, aborting activation` (`definition.md:79-81`). With
  Determinate the design would also need `nix.enable = false` and `determinateNix.enable = true`,
  and the den subject sets neither.
- **B8 destroys the very thing A3 proves.** This is the sharpest trade in the design. A golden
  image with the backup files already in place cannot prove the first-time takeover again — it has
  the creator's-host problem, one level down. So the design splits the two:
  - the golden image performs B8, and a `run` against it proves A1, A2, A4 and A5;
  - **A3 needs a `--cold` run** that clones `kdn-vmtest-base` instead of `kdn-vmtest-golden`, and
    pays B6 in the run. A3 therefore belongs to the cold path only.

  Version 1 keeps both paths and marks A3 as cold-only.

### Phase `run` — per checkpoint

| Step | Command shape | Time | State |
|---|---|---|---|
| R1 | `tart clone kdn-vmtest-golden kdn-vmtest-clone-<stamp>` | seconds | UNVERIFIED |
| R2 | `tart run --no-graphics …`, poll `tart exec … true` | about 10 s | UNVERIFIED for tart |
| R3 | On the **host**: `nix build '.#denConfigurations.host-darwin.system.build.toplevel'` | warm: seconds | UNVERIFIED for this attribute |
| R4 | `nix copy --to ssh-ng://admin@$(tart ip …) <toplevel>` | closure-bound | UNVERIFIED. The closure size of `host-darwin` is not measured |
| R5 | `tart exec … sudo nix-env -p /nix/var/nix/profiles/system --set <toplevel>` | seconds | — |
| R6 | `tart exec … sudo <toplevel>/activate` — this is A1 | 1 to 3 min | UNVERIFIED |
| R7 | A2 to A5 through `tart exec` | seconds | — |
| R8 | `tart stop`, then delete the clone **only** | seconds | — |

**Total `run` estimate: 5 to 15 minutes.** `definition.md:154` estimates 2 to 5 minutes per
checkpoint and marks it an estimate. I widen it, because R4 is unmeasured and the closure is
large.

R4 carries the one remaining `ssh` risk. `definition.md:232-242` proves a Nix-built `ssh` cannot
reach a **lume** guest on macOS 26, and it marks the cause — macOS local-network privacy —
UNVERIFIED. Whether the same fault hits a **tart** guest is UNVERIFIED. Two mitigations, in
order:

1. Run R4 with `/usr/bin/ssh` first on `PATH`. Nix picks `ssh` from `PATH`.
2. If that still fails, fall back to `nix-store --export` piped through `tart exec`. That path is
   UNVERIFIED and it risks a large stdio transfer, so it stays a fallback.

Every other guest command uses `tart exec`, so no other step depends on `ssh`.

## 7. Where it belongs — and why NOT `bundle-vm`

**`bundle-vm` can never hold this test. The design puts it behind a flake app instead.**

The reason is structural, not a matter of taste:

- `checks/bundles.nix:26-33` builds every bundle with `pkgs.linkFarm` over entries of the
  `checks` attribute set. So **every member of a bundle is a derivation**.
- A macOS guest needs three things the Nix sandbox refuses: the Hypervisor entitlement, network
  access, and a writable disk image outside the store. `repo-surface.research.md` records this as
  its third blocker, and `definition.md:206-208` repeats it as blocker 5.
- `checks/den-mvp/tests.nix:21` already states the same conclusion from the other side.
- The test needs `sudo` in the guest and it mutates a 120 GB disk image. Neither belongs in a
  derivation.

So `bundle-vm` stays **empty**. Its current comment says "No VM test exists — ./den-mvp/tests.nix
states why", and that wording implies a VM test would join it later. The plan corrects the comment
to say a VM test can never join, and it names the app.

**Placement:**

| Item | Value |
|---|---|
| Name | `apps.darwin-vm-test` |
| Shape | `pkgs.writeShellApplication` with `text = builtins.readFile ./hack/darwin-vm-test.sh` |
| Model | `apps.update` at `flake.nix:450-465`, which already reads `./flake-update.sh` |
| Bundle | **none.** `bundle-vm` stays empty |
| Check name | **none.** The test registers no `checks.<system>.*` attribute |
| Run time | `bake` 40 to 60 min, once. `run` 5 to 15 min |
| Per-edit loop | **Never.** `bundle-core` runs 11.1 s. This test is 30 to 80 times slower than that |
| When to run | By hand, before a Darwin hand-off, and after any change to a `darwin`-class aspect |

`checks/README.md` names the rule the design obeys: a non-VM bundle finishes in under 60 s. A
test measured in minutes does not belong in a per-edit bundle. This one is measured in minutes,
so it belongs in neither.

**Two safety rules the app must carry, both from the brief and both non-negotiable:**

1. **It never needs host `sudo`.** Apple Virtualization runs unprivileged. The script must refuse
   to run as root, so nobody adds a `sudo` by habit.
2. **It never deletes a VM image.** The script deletes only a guest whose name it generated in
   this run, under the fixed prefix `kdn-vmtest-clone-`. It refuses any other name. It never
   touches `kdn-vmtest-base` and never `kdn-vmtest-golden`. It never calls `limactl`, so it cannot
   reach the `nix-rosetta-builder` guest.
3. It must never set `kdn.rosetta-builder.guest.minFree` or `.maxFree` to a non-null value. A
   non-null value regenerates `lima.yaml`, and the start script then runs `limactl delete --force`
   (`modules/den/aspects/rosetta-builder.nix:31-37`). The subject sets neither, and the script sets
   no Nix option at all, so this holds by construction. The plan states it in a comment so a later
   editor does not break it.

## 8. The honest verdict

**Feasible, with one correction to the premise.**

| Question | Verdict |
|---|---|
| Can it work without host `sudo`? | **Yes.** Apple Virtualization is unprivileged, and `lume.research.md` proves a whole guest build with no host `sudo`. Guest `sudo` is needed and permitted. |
| Does a licence forbid it? | **No.** tart is FSL-1.1-ALv2 with no employee or revenue threshold, and only a Competing Use is barred. Apple's SLA grants two guests per host, and one is enough. |
| Does the run time make it useless? | **No, but it makes it a hand-run gate only.** 5 to 15 minutes per run rules out a per-edit loop for ever. |
| Can `bundle-vm` hold it? | **No, and it never can.** A bundle member is a derivation, and the Nix sandbox cannot run a macOS guest. `bundle-vm` stays empty. |
| Is the premise of the brief right? | **Partly.** `bundle-vm` is not "the slot this work fills". The work fills a flake app, and it corrects the `bundle-vm` comment so nobody makes the same assumption again. |

### The nearest achievable thing, if version 1 still stalls

If R4 or R6 blocks, this fallback holds most of the value at a fraction of the cost, and it needs
no VM:

**Run the activation script of `denConfigurations.host-darwin` under a fake root inside a
sandboxed check.** It gives class 2 — a script that runs instead of a script that grepped — and it
costs seconds. It gives neither class 1 nor class 3. This is a strictly smaller deliverable, and
it is not in the plan. Record it as the retreat position.

The alternative retreat is smaller still, and it needs no new code: accept the current five
Darwin checks, and record in `checks/den-mvp/README.md` that first-time activation is
**untested by design**. That is honest, and it is worse than the app.

## Open questions for the owner

1. **Should `bundle-vm` be deleted instead of corrected?** Section 7 shows no VM test can ever
   join it. `checks/bundles.nix:16-18` says a bundle name is "an infrastructure decision that
   belongs to the repository owner", so I do not delete it. The plan corrects the comment and
   leaves the name. Say which you want.
2. **Is Homebrew an acceptable dependency of a flake app?** tart must come from
   `brew install openai/tools/tart`, because the nixpkgs package is stale at 2.30.6 and marked
   unfree. No app in this repository depends on Homebrew today. The alternative is a
   `.flake.patches/` entry that bumps tart and corrects its licence, plus an upstream pull
   request. `definition.md:299-300` already asks for that pull request. Which comes first?
3. **Do you accept a 27.31 GB base image plus a 120 GB clone on the workstation disk?**
   `lume.research.md` records the free space on `/` as 208 GB at the end of its run. Two tart
   images plus a clone is a large part of the remainder.
4. **Is `denConfigurations.host-darwin` the right subject, or do you want a new
   `host-darwin-vm`?** `host-darwin` includes `kdn.rosetta-builder`, which cannot start in a
   guest. A new den host without that aspect gives a clean run, and it costs a new entity plus a
   new `den-eval-instantiate` pair. Section 2 marks the "does activation still exit 0" question
   UNVERIFIED, and the answer decides this.
5. **Which chain does this land on?** The design touches `flake.nix`, `checks/bundles.nix` and
   `checks/README.md` — all public. Confirm the public chain.
6. **Do you want the cold `--cold` path in version 1 at all?** A3 needs it, and it costs the
   Nix install per run. Dropping it makes version 1 cheaper and gives up the one assertion the
   creator's host can never make.
7. **Task 015 overlap.** `docs/tasks/2026-09/generalization/015-den-check-harness-platforms/` fixes
   the single-platform harness at `checks/den-mvp/harness.nix:84`. This design touches that harness
   nowhere, because the VM test is not a check. Confirm the two tasks stay separate.
