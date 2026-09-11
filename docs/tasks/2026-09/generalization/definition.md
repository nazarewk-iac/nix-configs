---
type: Task
status: in-progress
description: Checkpointed plan to make this repo's modules reusable by an external adopter without the creator's personal configuration.
timestamp: 2026-09-08T17:30:00+02:00
authored_by: agent
---

# Generalization plan

Make the modules reusable by an **external adopter** — anybody but this repo's creator. The adopter
gets none of the creator's personal configuration.

This file is the **hub**. It holds the checkpoint index, the dependency graph, the shared patterns,
and the readiness audit. Each checkpoint has its own task file under `docs/tasks/`. A fresh agent
reads this hub plus one task file.

## Context

The repo holds three module trees:

| Tree | Files | LOC | Nature |
|---|---|---|---|
| `modules/meta/` | 3 | 363 | A separate `lib.evalModules` universe (`class = "kdn-meta"`). The repo evaluates it **before** NixOS/Darwin/HM, then injects it as `specialArgs.kdnConfig`. |
| `modules/universal/` | 194 | 19,689 | Every context loads it. The `kdnConfig.util.*` guards scope it. |
| `modules/slots/` | 19 slots + 1 loader | 3,599 | Self-contained by rule. Emits into 5 `deferredModule` targets. `find` returns 20 `default.nix` files; `modules/slots/default.nix` is the recursive loader, not a slot. |

`modules/slots/` is already close to shareable. `modules/universal/` and `modules/meta/` carry
personal data: homelab topologies, sops files, YubiKey serials, WiFi SSIDs, real password hashes.

One concrete adopter use case drives the early checkpoints. The `rosetta-builder` module must work
in anybody's nix-darwin. Then an adopter builds multi-arch containers in their own repos.

## Decisions

| Question | Decision |
|---|---|
| Term for anybody but the creator | **external adopter**; their repo is the **adopter repo**. |
| Where code lives | **ONE public repo.** Do not add a separate library repo. |
| Where personal data lives | **ONE folder.** Modules reference it from there. This supersedes the scattered `kdn-*.nix`-next-to-the-module precedent. |
| Evaluator | **Lix 2.95.2.** Assume no CppNix and no Determinate Nix. |
| Adopter API | A call to a **minimal `mkSlots`** is fine. The requirement: a slot does not depend on the other module types. A slot does not need to become a plain module. |
| Retrofit `modules/universal` into slots | **No.** See [Direction](#direction-slots-or-den). |
| den | Evaluate it **early**, before any reimplementation work. |

## Checkpoint index

| # | Task file | Goal |
|---|---|---|
| 001 | [001-slots-sharing-readiness](001-slots-sharing-readiness/definition.md) | An adopter consumes `modules/slots` today. Fix the one bug that leaks private content. |
| 002 | [002-rosetta-builder-adopter-dropin](002-rosetta-builder-adopter-dropin/definition.md) | `rosetta-builder` works in an adopter's nix-darwin through a minimal `mkSlots`. |
| 003 | [003-nix-darwin-getting-started](003-nix-darwin-getting-started/definition.md) | A runbook from zero to a multi-arch build, with real pain points. |
| 004 | [004-den-spike](004-den-spike/definition.md) | Decide whether den can be the target framework. **Direction gate.** |
| 005 | [005-conditional-imports-requirement](005-conditional-imports-requirement/definition.md) | State what `modules/meta` solves, as a testable requirement. |
| 006 | [006-direction-decision](006-direction-decision/definition.md) | Choose slots or den as the reimplementation target. Gate: 004 + 005. |
| 007 | [007-depersonalize-slots](007-depersonalize-slots/definition.md) | Lift the creator's personal defaults and opinions out of shared slot options. |
| 008 | [008-sops-default-inventory](008-sops-default-inventory/definition.md) | An exact list of what depends on the default sops file, plus its key schema. |
| 009 | [009-personal-data-folder](009-personal-data-folder/definition.md) | One folder holds all personal data. The tree evaluates without it. |
| 010 | [010-flake-input-overhead](010-flake-input-overhead/definition.md) | Research, then maybe spike, ways to make a 106-node lock cheaper. |

## Dependency graph

```
wave 1 — first commit chain, no push
  001 ──► 002 ──► 003

wave 2 — direction gate; start as early as possible
  004 ──┬─► 006
  005 ──┘

wave 3 — independent of the direction; any time after 001
  007       008       010

wave 4 — needs the direction and the inventory
  006 + 008 ──► 009
```

Wave 2 runs early on purpose. It prevents one waste: work onto slots first, then the same work
onto den.

## Direction: slots or den

The plan does **not** retrofit `modules/universal` into slots. `modules/meta` solves a real
problem. Any target framework must solve it too:

> **Data drives conditional imports of third-party modules. Module `config` does not.** Example:
> the tree imports the Raspberry Pi 4 modules only when a host sets the correct
> `kdnConfig.features.*` flag. A plain `evalModules` cannot do this. It hits infinite recursion.
> `modules/meta` exists as a pre-pass for this reason.

Checkpoint 005 turns that into a written, testable requirement. Checkpoint 004 tests den against
it. Checkpoint 006 then picks slots or den, once. Nobody builds the option that loses.

den looks less abstract than the alternatives in that space, and it fits this problem better. One
unknown carried the decision: can an adopter import a den aspect as a plain drop-in module, with no
adoption of den?

**Answered on 2026-09-10 — PASS, with two limits.** 004 phase 1 measured it on den `main` and on
v0.18.0. `den.lib.aspects.resolve` returns a plain module an adopter imports with no den in their
own code. Criterion 1 (a `devenv` class) also passes, and criterion 4 (the mixed-aspect collision)
does not reproduce. So the kill criterion does not fire, and phase 2 builds `modules/den/`
additively.

The two limits shape any den work. An entity-parametric aspect and a den battery both drop to
`{ imports = [ ]; }` across the boundary, with no warning. And den stays a transitive lock node in
the adopter's own lock. See [004-den-spike/research.md](004-den-spike/research.md) for the
evidence, and the phase 1 verdict in [004's definition](004-den-spike/definition.md) for the four
conditions on phase 2.

**The creator prefers den for the adopter-facing configuration**, stated on 2026-09-10 and
conditional on the spike. The spike passed, so den is now the default choice and 006 carries the
burden of proof against it. The adopter still never adopts den: the adopter imports a plain module
that this repository resolves.

**Phase 2 milestone 1 landed on 2026-09-10.** `modules/den/` holds the loader, a `devenv` class, the
`rosetta-builder` aspect and one parallel host that never activates. The first adopter-facing den
output exists: `denModules.rosetta-builder`. The tree is additive — no file under `modules/slots/`,
`modules/universal/` or `modules/meta/` changed, and `darwinConfigurations` still lists the same
hosts. See [modules/den/README.md](../../../../modules/den/README.md) and the phase 2 section of
[004's definition](004-den-spike/definition.md). `mkSlots` stays the route for the other 17 slots.

Criterion 3 stays open until 005 states the conditional-imports requirement, so den is the
preferred direction, not yet a settled one. 006 records the score either way.

A Darwin host can also boot a NixOS guest. So 004 can prove Home Manager **activation**, not only
evaluation. microvm.nix supports a Darwin host at the revision this repo pins —
`hypervisorsOnDarwin = [ "qemu" "vfkit" ]`, and `vmHostPackages` selects plain `qemu` off Linux.
Treat that as a second phase of 004, behind the evaluation-level criteria. Every criterion that
decides the direction evaluates without a boot, so a boot alone decides nothing.

## Readiness audit — the 12 gaps

Severity is from an adopter's point of view. The listed checkpoint fixes the gap.

| # | Gap | Severity | Owner |
|---|---|---|---|
| 1 | `pre-push.sh` remote guard is inverted — it permits private content to the public remote | **P0** — **fixed 2026-09-10**, plus 15 tests | 001 |
| 2 | Nothing documents the overlay requirement `overlays = [ inputs.nix-configs.overlays.packages ]`; 7 slots use `pkgs.kdn.*` | High — **fixed 2026-09-10** in `docs/slots-for-adopters.md` and `templates/adopter/` | 001 |
| 3 | No adopter entry point — no template, no example `devenv.yaml`/`devenv.nix`, no adopter-facing doc | High — **fixed 2026-09-10**: `templates/adopter/` plus `docs/slots-for-adopters.md` | 001 |
| 4 | `devenv.yaml` pins the adopter's nixpkgs to the creator's nixpkgs fork through `follows: nix-configs/nixpkgs` | High — **fixed 2026-09-10**: the template points `nixpkgs` at nixos-unstable and says why | 001 |
| 5 | Personal data inside the slots tree — `data/slots-ssh-access.nix`, 176 LOC of hosts, LAN IPs, WAN ports, `*.kdn.im` zones | Medium | 007, 009 |
| 6 | Personal defaults in shared options — `kdn.jj.upstream.remote = "kdn"`, `alwaysBlockedMessagePatterns = [ "scratchpad" ]`, `opencode`'s hardwired `requesty` provider, `llm` examples with homelab FQDNs, and `identityAgentPatterns` (see below) | Medium | 007 |
| 7 | Slots ship the creator's opinions — `kdn.jj` installs a jj-only mandate as an agent rule; 5 slots read repo content through `${inputs.nix-configs}/.agents/…` | Medium | 007 |
| 8 | Two slots default to `enable = true` (`mcp/snoop`, `mcp/pretty-print`), against this repo's own side-effect-free rule | Medium | 007 |
| 9 | No CI check proves that a slot evaluates standalone and avoids universal options — `.agents/rules/slots-standalone.md` states the rule, nothing enforces it | Medium | 001 |
| 10 | `kdn.*` is a personal namespace on a shared library | Low — **do not rename**, the churn buys nothing | — |
| 11 | No slot assigns the `users` slot target | Low — **keep it** | — |
| 12 | Lock size: 106 nodes / 60 root inputs reach an adopter's lock as text | Low | 010 |

### Gap 1 was verified, then fixed

The old code skipped the denied-file and denied-message checks for every remote **except** the
private fork. The option docs (`modules/slots/jj/default.nix:54,59`) promise the opposite.

I reproduced it in a throwaway repo. The repo set `PRIVATE_REMOTE=<fork>`, and one commit added a
path in the denied set. The old code let a push to the public remote exit **0**, so the hook
permitted it.

**Fixed on 2026-09-10.** The guard now returns early for the private fork only
(`modules/slots/jj/pre-push.sh:93`). Two latent defects in the same script went with it: an empty
pattern list now fails loudly instead of passing in silence (lines 49-58), and a new ref asks git
for the commits the remote lacks instead of a `git diff` on a zero sha (line 132).

`checks/jj-experiments/test_prepush.py` holds 15 cases, and
[test_prepush.md](../../../../checks/jj-experiments/test_prepush.md) holds the prose. The suite
runs the plain script and bakes `PLACEHOLDER-*` patterns, so no real sensitive term enters the
tests. Two limits stay recorded there: a delete-only push to a public remote fails closed, and the
group does not prove the one-line `writeShellApplication` wrapper.

### Gap 6 has a measured example: `identityAgentPatterns`

`packages/kdn-ssh-access/module.nix:127` declares `identityAgentPatterns`, "Extra Host patterns
forced to `$SSH_AUTH_SOCK`". The option exists **only** to claw hosts back out of an `IdentityAgent`
blanket that a fork-only module writes for `Host *`. An adopter inherits the option and no blanket,
so for an adopter the option has no purpose.

This is the clearest form of gap 6: a shared public option that compensates for a personal module's
over-broad write. [tasks/ssh-agent-scoping.md](../ssh-agent-scoping/definition.md) holds the measured
mechanism and owns the fix.

### What an adopter can do today — 2026-09-10

The honest summary: **an adopter consumes `modules/slots` today.** Gaps 1 to 4 are fixed.
[slots-for-adopters.md](../../../slots-for-adopters.md) states the API, the overlay requirement and
what each slot writes into the adopter repo. [templates/adopter/](../../../../templates/adopter/README.md)
is the copy-ready shape.

What an adopter cannot do today is consume one slot as a plain module, with no `mkSlots` call.
Checkpoint 002 owns that for `rosetta-builder`, and 004 phase 2 owns the den route the creator
prefers.

## Corrections to earlier assumptions

Record these. Two of them remove work that looked necessary.

1. **An adopter does not fetch this repo's 60 inputs, and needs no SSH key to lock.** Lix's
   `lix/libexpr/flake/call-flake.nix` maps lock nodes with `builtins.mapAttrs`, so Lix never
   fetches a node that nothing references. `flake.cc` `computeLocks` keeps an input it already
   knows as metadata, with no network I/O. An adopter pays one whole-tree fetch (**4.1 MB**) plus
   ~106 lock nodes of text. So gap 12 is hygiene, not a blocker.
2. **Lix has no `lazy-trees`, and will not get it.**
   `nix --extra-experimental-features lazy-trees eval --expr 1` warns
   `unknown experimental feature 'lazy-trees'`. Lix states it will not use the upstream
   implementation. Lix also has a documented **flakes feature freeze**. No evaluator offers
   optional or lazy flake inputs. So no checkpoint may depend on a new evaluator feature.
3. **Do not adopt a third-party lock aggregator.** The candidates in this space are about one month
   old, and one maintainer runs each. They also solve the mirror-image problem — they consume many
   flakes cheaply. They do not export a small library from a big flake.

Checkpoint 010 re-verifies the open questions about `follows` laziness and `?dir=` subflakes. The
recommendation there is not yet settled.

## Shared patterns

### Pattern V1 — the drvPath equality gate

Before a refactor, record the derivation path of every host:

```bash
nix eval --raw '.#darwinConfigurations.<host>.config.system.build.toplevel.drvPath'
nix eval --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
```

After the refactor, record again and diff. An equal path proves the refactor is a no-op. This turns
a bulk refactor into a mechanical loop. It is the safety net for 007 and 009.

**Measured cost: 93 s for one warm Darwin host** (28 s user, 12 s system, all inputs already in the
store). 16 hosts take about 25 minutes in sequence. Use it as a checkpoint gate, not per edit. For
per-edit feedback use `devenv eval '<option.path>'`.

**Limit — the pattern proves nothing when a file appears or disappears.** `flake.nix:250` sets
`nix-configs = self`, so the whole tree hash enters every derivation this flake builds. A new file
changes every `drvPath`, even a file that no host reads. Measured on 2026-09-10: a dirty tree gave
`pz1xx9…` and the same tree clean gave `pi6dg3…` for one unchanged host.

So Pattern V1 covers an **edit** to a tracked file only. For a refactor that adds or moves a file,
prove additivity a second way — compare the output **names**, and diff one host's evaluated option
values. The 004 den milestone used
`nix eval --json '.#darwinConfigurations' --apply builtins.attrNames`.

**Exception — a den configuration is immune, so Pattern V1 works there.** den's evaluation never
reads `self`. Measured on 2026-09-10: `denConfigurations.host-darwin` kept the byte-identical
`drvPath` `7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move
**and** the addition of a second den host. So a den refactor gets the full gate that the slot and
universal routes cannot have. Gate on `denConfigurations`; `denDevenvShells` reads `self` through
`kdn.den.devenv.root`.

### Pattern V2 — the adopter-hostile eval

Any checkpoint that claims adopter safety must prove it two ways. First, with no SSH agent and no
usable key:

```bash
SSH_AUTH_SOCK= GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  nix eval …
```

Second, with no personal data folder present (after 009).

### Pattern V3 — the scratch adopter repo

Only one honest test of an adopter path exists: a flake **outside** this repo that declares one
input and enables one thing. Create it under `/tmp`. Never create it inside this repo's tree.

## Verification

| Level | Command | When |
|---|---|---|
| Option value | `devenv eval '<option.path>'` | per edit |
| Evaluation | `nix flake check` | per checkpoint |
| Adopter shape | Pattern V3 scratch flake | 001, 002 |
| No-op proof | Pattern V1 drvPath diff | 007, 009 |
| Hook behaviour | `checks/jj-experiments` per-remote cases | 001 |
| Format | `nix run .#kdn-nix-fmt --` | before each commit |
| Adopter safety | Pattern V2 | 001, 002, 009 |

Darwin hosts build on a Darwin machine, or through `remote=`. Do not run
`nom build .#darwinConfigurations.<host>.system` on Linux.

## Out of scope

- A rename of the `kdn.*` namespace (gap 10).
- Removal of the `users` slot target (gap 11).
- A retrofit of `modules/universal` into slots — see [Direction](#direction-slots-or-den).
- A move away from Lix.
- Any push. The creator reviews and pushes.

## Related work, already in `docs/tasks/`

- [tasks/slots-modules-architecture.md](../../2026-08/slots-modules-architecture/definition.md) — in progress. It
  states which architecture rules apply to slots. Checkpoint 001 links to it. Do not duplicate it.
- [tasks/rosetta-builder-i686-linux.md](../../2026-08/rosetta-builder-i686-linux/definition.md) — a known
  `rosetta-builder` limitation. Checkpoints 002 and 003 must tell an adopter about it.
- [tasks/multi-arch-rosetta-builder.done.md](../../2026-07/multi-arch-rosetta-builder/done.md) — the
  original builder work.
- [multi-arch-builder.md](../../../multi-arch-builder.md) and
  [multi-arch-container-builder.md](../../../multi-arch-container-builder.md) — the builder docs that exist
  today.

## Open research

Two research passes serve 008 and 010. Both are read-only. Neither changes a module. Each delivers
a `.research.md` sibling next to its task file. A third pass is complete and now has an owning task.

| Research | Feeds | Scope |
|---|---|---|
| Default sops file inventory | [008](008-sops-default-inventory/definition.md) | The four lists in 008 |
| Lix flake laziness | [010](010-flake-input-overhead/definition.md) | Q1-Q4 in 010 |
| Darwin VM testing — **done**, two `.research.md` files | [darwin-vm-testing.md](../darwin-vm-testing/definition.md) | A guest loop for the activation-level exit tests of 002, 003 and 009 |

The Darwin VM testing task carries one finding that **changes this hub**: a fresh-guest Darwin build
forces every `brew-tap--*` flake input, so gap 12 is a real blocker on that path, not only hygiene.
See the re-grade work item in that task.

Read the task file first. Each task file states its own method and deliverable, so you need no
extra brief.

A first attempt at both stopped part way on 2026-09-08. It kept two facts, and the task files now
hold them: 008 records one unguarded consumer from an evaluation trace; 010 records two grep-level
leads. No question got an answer.

Run the two passes at the same time. They touch different subsystems, so they do not conflict.
A subagent is session-scoped, so a new session starts each pass again from the scope above. Pick
the model per the model-tier rule: each pass gathers evidence and then verifies it, so `sonnet` fits.
Escalate only on a wrong or shallow claim.

## Constraints on every deliverable

These docs go to the public remote. Some paths in the working copy exist only on the private fork
chain. **Never cite a fork-only path** in any deliverable, example, or commit message. Never name
the creator's employer.

Check a path before you cite it:

```bash
PUB=refs/remotes/<public-remote>/main
git ls-tree -r --name-only "$PUB" -- <path> | head -1   # empty output means do not cite it
```

Beware: `<bookmark>@<remote>` is jj syntax. `git ls-tree` needs the git ref
(`refs/remotes/<remote>/<branch>`). It fails **silently** on a bad ref name. Every path then reads
as fork-only, and a real leak stays hidden.

Use `hosts/anji` as the Darwin example host; it is public. When a verified finding comes from a
fork-only file, state the finding and omit the path. Use a neutral placeholder for a private remote
name and a private host name.

### Language

Write every deliverable in strict ASD-STE100 Simple Technical English. See
`.agents/rules/simple-technical-english.md`. Then **verify your own output** against it. Check for
these four faults, in this order:

1. `-ing` forms — gerunds and participles. Keep them only inside a technical name.
2. Passive voice. Name the actor and use an active verb.
3. Sentence length. At most 20 words for an instruction, 25 for a description.
4. Synonym drift. Never use a second word for a term you already used.

## Process

All commits go through `jj`, in conventional commit format. Always pass `-m 'msg'` and
`-- <files>` explicitly. Never run `jj bookmark set`. Never create a git worktree in this repo.
