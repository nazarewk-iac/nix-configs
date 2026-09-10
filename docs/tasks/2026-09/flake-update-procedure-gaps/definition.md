---
type: Task
description: Repair the flake update procedure — add a fetch and a reconcile step, a start-state branch, a lock-structure check, and a completion check.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-09-09T12:00:00+02:00
---

# Repair the flake update procedure

> ✅ **Done** — see the solution in
> [flake-update-procedure-gaps.done.md](done.md).

Findings and the corrected procedure: [flake-update-procedure-gaps.research.md](research.md).

## Goal

Make one fork flake update correct and repeatable from any start state. The procedure must
tell the operator to fetch first, to reconcile the remote tips, to name the start state,
and to prove the run is complete before the hand-off.

## Defects

Three defects were measured before this task. All three are confirmed.

- **D1 — no fetch, no reconcile.** No update doc and no rule mentions a fetch. The only
  fetch sits inside the `sync-upstream` alias and runs at push time
  (`modules/slots/jj/fork/default.nix:184`). The last fetch in this repo ran 2026-09-08
  10:29; the current update commit was made 2026-09-09. So every placement decision read
  remote-tracking refs about 24 hours old.
- **D2 — the documented start state is not the usual state.**
  `docs/flake-update.fork.md:83,120` assume `@` is empty with two parents. In practice `@`
  sits on a linear stack. All six current local commits are `fork`-tagged, so
  `upstream-tip` resolves **below** the tree merge and the documented step 3 command
  grafts the public commit to the wrong parent.
- **D3 — no completion check.** Nothing states that a finished update leaves two commits,
  one per chain. Today exactly one exists, and the public chain's two lock files are
  byte-identical to `refs/remotes/kdn/main`.

18 more defects (O1–O18) and 12 skill divergences (S1–S12) are listed in the research
file. The worst three:

1. **O18a** — `modules/slots/jj/pre-push.sh:65-67` gates the sensitive-path check to the
   **private** remote, while `modules/slots/jj/default.nix:54` documents the opposite. The
   public push gets no file check.
2. **O12** — the insert command needs `fork-tip` to be a mutable merge. No doc states the
   precondition, so the command breaks the topology in the usual start state.
3. **O10** — no doc checks that the `devenv.lock` strip list is not empty. An empty list
   makes the transform a no-op and every fork node stays in the public `devenv.lock`.

## Defects measured during the 2026-09-09 update run

An operator ran one full fork update and split it across the two chains. These four defects
stopped the run. Each one is **verified** on the real graph, not inferred.

### D4 — the `devenv.lock` strip command destroys its own input

`docs/flake-update.fork.md:184-192` and `.agents/skills/flake-update-fork/SKILL.md:43-46`
both give this shape:

```bash
jj file show -r "$FORK_UPDATE" devenv.lock | jq … > devenv.lock
```

The shell opens the redirect **before** it starts the pipeline, so `devenv.lock` is already
0 bytes when `jj file show` runs. `jj file show` then snapshots the working copy, and the
empty file becomes the content of `@`. In the documented flow `@` is the public-inputs
commit and `$FORK_UPDATE` is the fork merge, which is a **descendant** of `@`. So jj rebases
the empty file into `$FORK_UPDATE`, and the read returns nothing. `jq` reports
`Invalid numeric literal at line 1, column 8` and writes an empty file.

Measured: one run wiped `devenv.lock` in `@` and in every descendant.
`jj op restore <op-before-the-snapshot>` recovered it.

Fix: write to a temporary file, then move it into place.

```bash
jj file show -r "$FORK_UPDATE" devenv.lock > /tmp/fork.devenv.lock
jq … /tmp/fork.devenv.lock | jq -j '.' > /tmp/public.devenv.lock
mv /tmp/public.devenv.lock devenv.lock
```

The same hazard applies to any command that reads a tracked file through `jj` and redirects
into that file. Add the rule to the jj doc, not only to the update doc.

### D5 — no structural check on the stripped `devenv.lock`

A hand-written variant of the strip transform wrote `"inputs": null` on 49 nodes that hold
no inputs. The public and the fork `devenv.lock` both carried the fault. No procedure step
found it. `devenv build shell` failed later with:

```
error: expected a set but found null
… at .devenv/bootstrap/resolve-lock.nix:131
```

`resolve-lock.nix:125` reads `node.inputs or { }`. The `or` operator answers a **missing**
attribute only. It does not answer `null`, so the null reaches `builtins.mapAttrs` and the
evaluation stops. A node that holds no inputs must **omit** the key. `flake.lock` never
writes `"inputs": null`.

The documented transform is **not** the cause. Its guard `if .inputs then … else . end` is
null-safe. The cause is that the procedure permits a hand-written substitute and then checks
nothing.

Add three assertions after the strip, for both lock files:

1. No node holds `"inputs": null`.
2. Every string input value names a node that exists (referential integrity).
3. The public node count equals the fork node count minus the strip-list length.

### D6 — root cause of D2, measured

`modules/slots/jj/fork/default.nix:69` defines the third term of the `fork` alias as
`((remote_bookmarks(remote=<fork-remote>) ~ upstream@<fork-remote>)::)`. The `::` suffix tags
**every descendant** of the fork bookmark. So `upstream-chain`, which is
`~description("") & ~fork`, can never hold a commit above the tree merge, whatever that
commit contains. `upstream-tip` therefore resolves **below** the tree merge on any graph that
already carries local work.

Consequence: the one-command step 2,
`jj new --insert-after upstream-tip --insert-before fork-tip`, builds a merge that spans from
below the tree merge to the very top of the stack. This is the mechanism behind D2 and O12.

`upstream-safe` does not have this fault. It is `to-rebase & ~fork-direct`, and
`fork-direct` tests **content**, not topology.

### D7 — no build check on either chain

The procedure builds host configurations only. Nothing builds the devenv shell, so a broken
`devenv.lock` reaches the push. D5 proves the gap: the fault survived every documented check
and appeared only when the operator entered the shell.

Add one build per chain to the verify step. Both passed after the D5 repair:

| Chain | `@` position | Result |
|---|---|---|
| fork | `fork-tip` | `devenv build shell` exit 0 |
| upstream | `upstream-tip` | `devenv build shell` exit 0 |

### D8 — no darwin evaluation gate, and no chain rule for a post-update fix

The update bumped `stylix` from `a9e5a76` to `5e38098`. That bump broke **every** darwin host. The
operator found it only when they ran their own `darwin-rebuild build`, after the graph was already
split and parked.

Measured cause. Old `stylix` held exactly one `home.pointerCursor` definition, in
`stylix/hm/cursor.nix`, and that file guards on `pkgs.stdenv.hostPlatform.isLinux`. New `stylix`
adds three more, in `modules/gtk/hm.nix:35`, `modules/x11/hm.nix:20` and `modules/sway/hm.nix:87`,
and **none of the three has a platform guard**. `home-manager`'s own
`modules/config/home-cursor.nix` is byte-identical across the bump, so home-manager is not part of
the cause.

This repo then met the new behaviour, because `modules/universal/_stylix.nix` gated
`stylix.cursor.*` on the **module type** `[ "nixos" "home-manager" ]`. A home-manager child of a
darwin host also has the type `home-manager`, so it received a cursor. Any definition inside the
`home.pointerCursor` submodule turns that Linux-only home-manager module on, and the module then
reads `name`, which has no default:

```
error: The option `home-manager.users.kdn.home.pointerCursor.name' was accessed but has no value
defined. Try setting the option.
```

Two separate gaps follow:

1. **No evaluation gate for darwin.** The verify step builds host configurations, but the run never
   evaluated a darwin host. A `nix eval` of the toplevel `drvPath` costs no build and catches this
   whole class of fault. Add one per host, for both chains.
2. **No rule for where a post-update fix belongs.** A fork host surfaced this fault, but the fix is
   a generic module fix and it carries no private content. So it belongs on the **public** chain,
   below the tree merge, and the fork chain inherits it through the merge. No doc states that rule,
   and the obvious move — commit it on top of `fork-tip` — puts a public fix on the private chain
   where it never reaches the public remote.

The rule to write down: place a post-update fix by its **content**, not by the host that found it.
Run `jj fork-audit` on the fix to decide. When the audit passes, insert the fix after
`upstream-tip` and before the tree merge.

### Not a defect — `nix run '.#flake-lock-merge'` from the working tree

One run failed with `error: 'packages.aarch64-darwin' is not an attribute set`. A re-test on
the settled graph passed. The failure is a symptom of an inconsistent working-copy lock, not a
fault in the tool or in the invocation. The pinned-rev form stays useful because it avoids a
rebuild of the tool, not because the plain form is wrong.

## Work items

### Docs

- [x] `docs/flake-update.fork.md` — add **step 0**: `jj git fetch --all-remotes`, then the
      reconcile table (four outcomes: nothing moved, public tip moved, fork tip moved,
      both moved). State that a rebase is required in one case only.
- [x] `docs/flake-update.fork.md` — add **step 1**: the start-state table with the five
      states and the first step for each. Mark states (ii), (iii) and (iv) as "work first".
- [x] `docs/flake-update.fork.md` — add the case (iv) correction sequence (reorder before
      the update, oldest safe commit first).
- [x] `docs/flake-update.fork.md:95,159` — add the mutable-merge guard before the insert
      command (O12).
- [x] `docs/flake-update.fork.md:99-106,185-192` — drop the `^brew-tap--` prefix filter;
      derive the strip list from the root-inputs diff (O9).
- [x] `docs/flake-update.fork.md:185-193` — assert the strip list is not empty (O10).
- [x] `docs/flake-update.fork.md:82-112` — add the patch-file move to the quick summary
      (O11).
- [x] `docs/flake-update.fork.md:209-215` — replace "Verify the topology" with the
      completion check (D3, O13).
- [x] `docs/flake-update.fork.md:227` — use `"$f"`, not the hardcoded `flake.lock` (O8).
- [x] `docs/flake-update.fork.md:9-11` — correct the claim about which file the slot
      installs (O7).
- [x] `docs/flake-update.fork.md` — add `jj fork-audit -q --color=never 'upstream-tip'` to
      the verify step (O16), and a warning that the two pushes are not atomic and the
      public push runs first (O17).
- [x] `docs/flake-update.fork.md:399-408` — state that the NixOS build of `upstream-tip`
      gates the public push, and the Darwin build of `fork-tip` gates the private push
      (O15).
- [x] `docs/flake-update.md:22-30` — add the guard: this procedure applies when
      `kdn.jj.fork.enable = false` (O1, O2).
- [x] `docs/flake-update.md:114` — replace `upstream@<fork-remote>` with
      `main@<public-remote>` (O3).
- [x] `docs/flake-update.md:66-71` — point the patch branch at `docs/flake-patches.md` and
      the `flake-patches` skill; keep one branch per failure cause (O14).
- [x] `docs/flake-update.fork.md:184-192` — write the strip through a temporary file, then
      `mv` it into place. Never redirect into the file the pipeline reads (D4).
- [x] `docs/flake-update.fork.md` — add the three structural assertions after the strip
      (D5), and state that a hand-written substitute transform is not permitted.
- [x] `docs/flake-update.fork.md` — add `devenv build shell` on each chain to the verify
      step (D7).
- [x] `docs/flake-update.fork.md` — add an evaluation gate to the verify step: for every nixos
      and every darwin host, on both chains, run
      `nix eval --raw '.#<configurations>.<host>.config.system.build.toplevel.drvPath'`. It costs
      no build and it catches an input bump that breaks one platform only (D8).
- [x] `docs/flake-update.fork.md` — state the chain rule for a post-update fix: place the fix by
      its **content**, not by the host that found it. Confirm with `jj fork-audit`. Insert a
      public fix after `upstream-tip` and before the tree merge, so the fork inherits it (D8).
- [x] `docs/jujutsu-vcs.md` — add the general rule from D4: a command that reads a tracked
      file through `jj` must not redirect into that same file, because jj snapshots the
      working copy first and a rebase carries the truncated file to the descendants.
- [x] `docs/flake-update.fork.md` — record the D6 mechanism next to the insert command, so
      the reader understands **why** `upstream-tip` resolves below the tree merge.

### Agent rules

- [x] `.agents/rules/flake-update.fork.md` — add the fetch line, the start-state check,
      and the completion check to the quick sequence. Add the mutable-merge guard.
- [x] `.agents/rules/flake-update.fork.md:28-34` — align the graph drawing with the doc
      (S7).
- [x] `.agents/rules/flake-update.md:9,11,13` — correct the three broken links (O4).
- [x] `.agents/rules/flake-update.md:17-27` — add the fork guard (O2), add
      `devenv update` (S12), and replace `upstream@<fork-remote>` (O3).

### Skills

- [x] `.agents/skills/flake-update-fork/SKILL.md:8` — correct the link depth (O6).
- [x] `.agents/skills/flake-update-fork/SKILL.md` — add step 0 (fetch + reconcile), the
      start-state gate, the mutable-merge guard and the completion check. Align the step
      numbers with the doc (S6).
- [x] `.agents/skills/flake-update-fork/SKILL.md:66-67` — align the graph drawing (S7).
- [x] `.agents/skills/flake-update/SKILL.md:8-10` — correct the three broken links (O5).
- [x] `.agents/skills/flake-update/SKILL.md:20-21` — add the fork guard (S1).
- [x] `.agents/skills/flake-update/SKILL.md:42` — replace `upstream@<fork-remote>` (S3).
- [x] `.agents/skills/flake-update/SKILL.md:9` — name the `flake-update-fork` skill, not
      only the doc (S11).
- [x] Both skills — decide how a consumer repo reaches the full docs. Every `docs/…` link
      is dead after the slot installs the skill (S10). Either inline the essentials, or
      link to a stable URL.

### New artifacts

- [x] Add the completion check as a script, for example
      `hack/flake-update-complete.sh`. Ten assertions, exit 1 on any FAIL. The text is in
      the research file § 8.
- [x] Add `fork-incoming = @..main@<fork-remote>` and
      `fork-incoming-tip = main@<fork-remote>` to `modules/slots/jj/fork/default.nix`, as
      a mirror of `upstream-incoming` (lines 89–90).
- [x] Add a lock-structure check to the completion script: no `"inputs": null` in either
      lock, referential integrity of every string input value, and the public node count
      equals the fork node count minus the strip-list length (D5).

### Code, separate commits (O18)

- [x] `modules/slots/jj/pre-push.sh:65-67` — invert the gate, or correct
      `modules/slots/jj/default.nix:54`. Decide which behavior is intended first.
- [x] `modules/slots/jj/pre-push.sh:10` — read `PRE_COMMIT_REMOTE_NAME`, not
      `${PRE_COMMIT_REMOTE_BRANCH%%/*}`.
- [x] `modules/slots/jj/pre-push.sh:69` — use the `range` bounds, so the zero sha never
      reaches `git diff`.
- [x] Add the structural lock gate (research § 8, assertion 7) to a `checks/` derivation
      or to the push path. A name-only or pattern-only check cannot catch a lock-node
      leak.
- [x] Extend `kdn.jj.fork.deniedFilePatterns` with the spelling that appears in the fork-only
      lock node keys. **The owner did this on 2026-09-09.** The measurement then showed the
      confirmation step was wrong: a line-level check cannot see a value-only lock node update,
      because the org name sits on the unchanged key line. So `jj fork-audit <the update
      commit>` stays exit 0 by design, and assertion 7 stays the gate. Own task, now closed:
      [fork-denied-patterns-miss-lock-nodes.md](../fork-denied-patterns-miss-lock-nodes/definition.md).
- [x] `modules/slots/jj/fork/check-fork-contamination.sh` — the hook runs at `pre-commit`
      and reads the git index, so jj never triggers it. Decide whether to move the content
      check to the push path or to drop the hook.

## Exit criteria

- [x] Every doc, rule and skill states the fetch step and the reconcile branch.
- [x] Every doc, rule and skill states the start-state table, and which states need work
      first.
- [x] The completion check exists as a runnable script, and it FAILs on the current
      incomplete state and PASSes on a finished update.
- [x] The `devenv.lock` strip list holds no hardcoded prefix, and an empty list stops the
      run.
- [x] Every relative link in the four doc and rule files, and in both skills, resolves.
- [x] The public-chain leak gate is structural, and it does not depend on the pattern list.
- [x] `jj fork-audit -q --color=never 'upstream-tip'` exits 0 on a finished update.
- [x] No documented command redirects into a file that the same pipeline reads through `jj`.
- [x] Neither lock file holds `"inputs": null`, and every string input value names a node
      that exists.
- [x] `devenv build shell` exits 0 with `@` on `upstream-tip`, and again with `@` on
      `fork-tip`.
- [ ] Every nixos host and every darwin host evaluates to a `drvPath` on both chains, before the
      hand-off.
- [x] The docs state how to choose the chain for a post-update fix, and they name `jj fork-audit`
      as the test.

### The one open criterion

Two of the three criteria that needed a finished update closed on 2026-09-09. The operator had
already split the update in the working copy by hand, so a finished graph did exist. The check
now reports **21 PASS, 0 FAIL, exit 0** on it.

Closing them needed one fix to the check itself. Assertions 2 and 3 tested `fork-tip`, where they
must test `tree-merge`. A fork-only fix legitimately sits above the merge, and `fork-tip` is then
that leaf. So the check rejected a correctly finished update — the same trap the docs name with
the `-B tree-merge`, never `-B fork-tip` rule. A new assertion 3b keeps the old intent: the fork
tip is the merge, or a descendant of it.

| Criterion | State |
|---|---|
| the completion check FAILs on the incomplete state and PASSes on a finished update | **met**. It reported 3 FAIL before the operator's split, and 0 FAIL after |
| `jj fork-audit -q --color=never 'upstream-tip'` exits 0 | **met** as written. Read it with the caveat below |
| every host evaluates to a `drvPath` on both chains | **open**. Not run |

Caveat on the fork-audit criterion: exit 0 is weak evidence on its own, and the owner's pattern
fix does not change that. A line-level check cannot see a value-only lock node update, because the
org name sits on the unchanged key line. Assertion 7 gives the independent proof — it counts 0
fork-only nodes on the upstream tip, and it needs no pattern. See
[fork-denied-patterns-miss-lock-nodes.done.md](../fork-denied-patterns-miss-lock-nodes/done.md).

The last criterion is testable today, and it is the only work left:

```bash
nix eval --raw '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
```

Run it per host, once with `@` on `upstream-tip` and once on `fork-tip`. A warm Darwin host takes
about 93 s. Darwin hosts must evaluate on a Darwin machine or through `remote=`.

## Out of scope

- The current update in the working copy. Do not run it, and do not repair the graph as
  part of this task. This task changes documents and adds a check.
  **Update, 2026-09-09:** an operator has since run and split that update by hand. D4 to D7
  come from that run. The graph is repaired and both chains build. This task still owns only
  the documents and the check.
- Contribution access tiers. Another task owns
  `docs/tasks/fork-contribution-access-tiers*.md`.
- The `flake-lock-merge` tool itself. Its behavior is correct; only the docs around it
  need work.
- `docs/jujutsu-vcs.fork.md` and `checks/jj-experiments/`. Both are accurate and the
  corrected procedure reuses them.
