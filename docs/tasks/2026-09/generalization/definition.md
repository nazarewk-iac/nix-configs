---
type: Task
status: in-progress
description: Checkpointed plan to make this repo's modules reusable by an external adopter without the creator's personal configuration.
timestamp: 2026-09-08T17:30:00+02:00
authored_by: agent
---

# Generalization plan

Make the modules reusable by an **external adopter** — anybody but this repo's creator — with
none of the creator's personal configuration.

This file is the **hub**. It holds the checkpoint index, the dependency graph, the shared
patterns, and the readiness audit. Each checkpoint has its own task file under `docs/tasks/`.
A fresh agent reads this hub plus one task file.

## Context

The repo holds three module trees:

| Tree | Files | LOC | Nature |
|---|---|---|---|
| `modules/meta/` | 3 | 363 | A separate `lib.evalModules` universe (`class = "kdn-meta"`), evaluated **before** NixOS/Darwin/HM and injected as `specialArgs.kdnConfig`. |
| `modules/universal/` | 194 | 19,689 | Loaded in every context, scoped by `kdnConfig.util.*` guards. |
| `modules/slots/` | 20 | 3,168 | Self-contained by rule. Emits into 5 `deferredModule` targets. |

`modules/slots/` is already close to shareable. `modules/universal/` and `modules/meta/` carry
personal data: homelab topologies, sops files, YubiKey serials, WiFi SSIDs, real password hashes.

One concrete adopter use case drives the early checkpoints: the `rosetta-builder` module must work
in anybody's nix-darwin, so an adopter builds multi-arch containers in their own repos.

## Decisions

| Question | Decision |
|---|---|
| Term for anybody but the creator | **external adopter**; their repo is the **adopter repo**. |
| Where code lives | **ONE public repo.** A separate library repo is rejected. |
| Where personal data lives | **ONE folder**, referenced from there. This supersedes the scattered `kdn-*.nix`-next-to-the-module precedent. |
| Evaluator | **Lix 2.95.2.** No CppNix or Determinate Nix assumptions. |
| Adopter API | Calling a **minimal `mkSlots`** is fine. The requirement is that slots do not depend on the other module types — not that slots become plain modules. |
| Retrofit `modules/universal` into slots | **No.** See [Direction](#direction-slots-or-den). |
| den | Evaluate **early**, before any reimplementation work. |

## Checkpoint index

| # | Task file | Goal |
|---|---|---|
| 001 | [generalization-001-slots-sharing-readiness.md](001-slots-sharing-readiness/definition.md) | An adopter consumes `modules/slots` today. Fix the one bug that leaks private content. |
| 002 | [generalization-002-rosetta-builder-adopter-dropin.md](002-rosetta-builder-adopter-dropin/definition.md) | `rosetta-builder` works in an adopter's nix-darwin through a minimal `mkSlots`. |
| 003 | [generalization-003-nix-darwin-getting-started.md](003-nix-darwin-getting-started/definition.md) | A runbook from zero to a multi-arch build, with real pain points. |
| 004 | [generalization-004-den-spike.md](004-den-spike/definition.md) | Decide whether den can be the target framework. **Direction gate.** |
| 005 | [generalization-005-conditional-imports-requirement.md](005-conditional-imports-requirement/definition.md) | Write down what `modules/meta` actually solves, as a testable requirement. |
| 006 | [generalization-006-direction-decision.md](006-direction-decision/definition.md) | Choose slots or den as the reimplementation target. Gated on 004 + 005. |
| 007 | [generalization-007-depersonalize-slots.md](007-depersonalize-slots/definition.md) | Lift the creator's personal defaults and opinions out of shared slot options. |
| 008 | [generalization-008-sops-default-inventory.md](008-sops-default-inventory/definition.md) | An exact list of what depends on the default sops file and its key schema. |
| 009 | [generalization-009-personal-data-folder.md](009-personal-data-folder/definition.md) | One folder holds all personal data. The tree evaluates without it. |
| 010 | [generalization-010-flake-input-overhead.md](010-flake-input-overhead/definition.md) | Research, then maybe spike, smoothing out a 106-node lock. |

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

Wave 2 runs early on purpose. Reimplementing modules onto slots and then again onto den is the
waste this ordering prevents.

## Direction: slots or den

The plan does **not** retrofit `modules/universal` into slots. `modules/meta` solves a real
problem, and any target framework must solve it too:

> **Conditional imports of third-party modules, driven by data rather than by module `config`.**
> Example: the Raspberry Pi 4 modules, imported only when a host sets the matching
> `kdnConfig.features.*` flag. A plain `evalModules` cannot do this without infinite recursion,
> which is why `modules/meta` exists as a pre-pass.

Checkpoint 005 turns that into a written, testable requirement. Checkpoint 004 tests whether den
satisfies it. Checkpoint 006 then picks slots or den, once — and the losing option is not built.

den looks less abstract and better matched to this problem than the alternatives in that space.
The load-bearing unknown is whether an adopter imports a den aspect as a plain drop-in module
**without adopting den** — see 004, criterion 2. That criterion decides it.

## Readiness audit — the 12 gaps

Severity is from an adopter's point of view. The owning checkpoint fixes it.

| # | Gap | Severity | Owner |
|---|---|---|---|
| 1 | `pre-push.sh` remote guard is inverted — private content is permitted to the public remote | **P0** | 001 |
| 2 | The overlay requirement `overlays = [ inputs.nix-configs.overlays.packages ]` is undocumented; 7 slots use `pkgs.kdn.*` | High | 001 |
| 3 | No adopter entry point — no template, no example `devenv.yaml`/`devenv.nix`, no adopter-facing doc | High | 001 |
| 4 | `devenv.yaml` pins the adopter's nixpkgs to the creator's nixpkgs fork through `follows: nix-configs/nixpkgs` | High | 001 |
| 5 | Personal data inside the slots tree — `modules/slots/ssh-access/kdn-graph.nix`, 176 LOC of hosts, LAN IPs, WAN ports, `*.kdn.im` zones | Medium | 007, 009 |
| 6 | Personal defaults in shared options — `kdn.jj.upstream.remote = "kdn"`, `alwaysBlockedMessagePatterns = [ "scratchpad" ]`, `opencode`'s hardwired `requesty` provider, `llm` examples with homelab FQDNs | Medium | 007 |
| 7 | Slots ship the creator's opinions — `kdn.jj` installs a jj-only mandate as an agent rule; 5 slots read repo content through `${inputs.nix-configs}/.agents/…` | Medium | 007 |
| 8 | Two slots default to `enable = true` (`mcp/snoop`, `mcp/pretty-print`), against this repo's own side-effect-free rule | Medium | 007 |
| 9 | No CI check that a slot evaluates standalone or avoids universal options — `.agents/rules/slots-standalone.md` states the rule, nothing enforces it | Medium | 001 |
| 10 | `kdn.*` is a personal namespace on a shared library | Low — **do not rename**, the churn buys nothing | — |
| 11 | The `users` slot target is unused — no slot assigns it | Low — **keep it** | — |
| 12 | Lock size: 106 nodes / 60 root inputs reach an adopter's lock as text | Low | 010 |

### Gap 1 is verified, not theoretical

`modules/slots/jj/pre-push.sh:64-67` skips the denied-file and denied-message checks for every
remote **except** the private fork, while the option docs
(`modules/slots/jj/default.nix:54,59`) promise the opposite.

Reproduced in a throwaway repo with `PRIVATE_REMOTE=<fork>` and a commit that adds a path matching
a denied pattern. Current code: push to the public remote exits **0** (allowed). With the guard
inverted: public exits **1** (blocked), fork exits **0** (allowed) — the documented intent.

## Corrections to earlier assumptions

Record these. Two of them remove work that looked necessary.

1. **An adopter does not fetch this repo's 60 inputs, and needs no SSH key to lock.** Lix's
   `lix/libexpr/flake/call-flake.nix` maps lock nodes with `builtins.mapAttrs`, so an
   unreferenced node is never fetched. `flake.cc` `computeLocks` keeps an existing input as
   metadata with no network I/O. An adopter pays one whole-tree fetch (**4.1 MB**) plus ~106 lock
   nodes of text. So gap 12 is hygiene, not a blocker.
2. **`lazy-trees` is not available on Lix and is not coming.**
   `nix --extra-experimental-features lazy-trees eval --expr 1` warns
   `unknown experimental feature 'lazy-trees'`. Lix states it will not use the upstream
   implementation. Lix also has a documented **flakes feature freeze**. Optional or lazy flake
   inputs do not exist anywhere. So no checkpoint may depend on an evaluator feature landing.
3. **Do not adopt a third-party lock aggregator.** The candidates in this space are about one
   month old and single-maintainer, and they solve the mirror-image problem — consuming many
   flakes cheaply, not exporting a small library from a big flake.

Checkpoint 010 re-verifies the remaining open questions about `follows` laziness and `?dir=`
subflakes, because the recommendation there is not yet settled.

## Shared patterns

### Pattern V1 — the drvPath equality gate

Before a refactor, record the derivation path of every host:

```bash
nix eval --raw '.#darwinConfigurations.<host>.config.system.build.toplevel.drvPath'
nix eval --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
```

After the refactor, record again and diff. An unchanged path proves the refactor is a no-op.
This turns a bulk refactor into a mechanical loop, and it is the safety net for 007 and 009.

**Measured cost: 93 s for one warm Darwin host** (28 s user, 12 s system, all inputs already in
the store). 16 hosts is about 25 minutes in sequence. Use it as a checkpoint gate, not per edit.
For per-edit feedback use `devenv eval '<option.path>'`.

### Pattern V2 — the adopter-hostile eval

Any checkpoint that claims adopter safety proves it two ways:

```bash
# no SSH agent, no usable key
SSH_AUTH_SOCK= GIT_SSH_COMMAND='ssh -o BatchMode=yes -o IdentitiesOnly=yes -o IdentityFile=/dev/null' \
  nix eval …
```

and with the personal data folder absent (after 009).

### Pattern V3 — the scratch adopter repo

The only honest test of an adopter path is a flake **outside** this repo that declares one input
and enables one thing. Create it under `/tmp`, never inside this repo's tree.

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

Darwin hosts build on a Darwin machine or through `remote=`. Do not run
`nom build .#darwinConfigurations.<host>.system` on Linux.

## Out of scope

- Renaming the `kdn.*` namespace (gap 10).
- Deleting the `users` slot target (gap 11).
- Retrofitting `modules/universal` into slots — see [Direction](#direction-slots-or-den).
- Switching off Lix.
- Any push. The creator reviews and pushes.

## Related work already tracked

- [tasks/slots-modules-architecture.md](../../slots-modules-architecture.md) — in progress;
  documents which architecture rules apply to slots. Checkpoint 001 links to it, and must not
  duplicate it.
- [tasks/rosetta-builder-i686-linux.md](../../rosetta-builder-i686-linux.md) — a known
  `rosetta-builder` limitation. Checkpoints 002 and 003 must tell an adopter about it.
- [tasks/multi-arch-rosetta-builder.done.md](../../multi-arch-rosetta-builder.done.md) — the
  original builder work.
- [multi-arch-builder.md](../../../multi-arch-builder.md) and
  [multi-arch-container-builder.md](../../../multi-arch-container-builder.md) — the existing builder docs.

## Open research — resume next session

Two research passes were stopped part way on 2026-09-08, before they reported. **Relaunch both.**
A subagent is session-scoped, so a new session cannot resume the old one — start each again from
the scope below. Both are read-only research. Neither changes a module.

| Research | Feeds | Scope | State when stopped |
|---|---|---|---|
| Default sops file inventory | [008](008-sops-default-inventory/definition.md) | The four lists in 008 | Reached an evaluation trace that proved one unguarded consumer. That finding is already written into 008. |
| Lix flake laziness | [010](010-flake-input-overhead/definition.md) | Q1-Q4 in 010 | Produced two grep-level leads, both written into 010. No question answered. |

Read the owning task file first. Each one states its own method and deliverable, so no extra
briefing is needed. Both deliver a `.research.md` sibling.

Run them at the same time — they touch different subsystems and do not conflict. Pick the model per
the tiering rule: these are evidence-gathering passes with a verification loop, so `sonnet` fits;
escalate only on a wrong or shallow claim.

## Writing constraint for every deliverable

These docs go to the public remote. Some paths in the working copy exist only on the private fork
chain. **Never cite a fork-only path** in any deliverable, example, or commit message, and never
name the creator's employer.

Check a path before you cite it:

```bash
PUB=refs/remotes/<public-remote>/main
git ls-tree -r --name-only "$PUB" -- <path> | head -1   # empty output means do not cite it
```

Beware: `<bookmark>@<remote>` is jj syntax. `git ls-tree` needs the git ref
(`refs/remotes/<remote>/<branch>`), and it fails **silently** on a bad ref name — which reads as
"fork-only" for every path and hides real leaks.

Use `hosts/anji` as the Darwin example host; it is public. When a verified finding comes from a
fork-only file, state the finding and omit the path. Use a neutral placeholder for private remote
and host names.

## Process

All commits go through `jj`, in conventional commit format, always with `-m 'msg'` and
`-- <files>` passed explicitly. Never `jj bookmark set`. Never a git worktree in this repo. Write
all prose, comments, and commit messages in strict ASD-STE100 Simple Technical English.
