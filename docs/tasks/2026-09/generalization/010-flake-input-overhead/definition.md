---
type: Task
description: Research, then maybe spike, ways to smooth out a 106-node flake lock on Lix, for both the creator's own cost and an adopter's cost.
status: open
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 010 — flake input overhead

Hub: [../generalization-plan.md](../definition.md). Independent of everything after 001.
Run it whenever.

Goal: decide whether anything measurably reduces the cost of this repo's flake inputs. Research
first. Spike only if the research finds a worthwhile target.

## The measured baseline

| Metric | Value |
|---|---|
| `flake.lock` | 106 nodes, 60 root inputs |
| `devenv.lock` | 112 nodes |
| Repo tree | 4.1 MB, 2292 revisions |
| Evaluator | Lix 2.95.2, aarch64-darwin |
| devenv | 2.2.3 |

100 locks is "bordering on massive", not massive. Treat this checkpoint as an optimization with a
real chance of a negative result. A negative result is a valid, useful outcome. Write it down. Then
close the checkpoint.

## What is already settled

Do not re-research these.

1. **An adopter does not fetch the 60 inputs, and needs no SSH key to lock.** Lix's
   `lix/libexpr/flake/call-flake.nix` maps lock nodes with `builtins.mapAttrs`, so Lix never
   fetches an unreferenced node. `flake.cc` `computeLocks` keeps an input that already exists as
   metadata, with no network I/O. An adopter pays one 4.1 MB tree fetch plus ~106 lock nodes of
   text.
2. **`lazy-trees` is not on Lix, and Lix will not add it.**
   `nix --extra-experimental-features lazy-trees eval --expr 1` warns
   `unknown experimental feature 'lazy-trees'`. Lix states it will not use the upstream
   implementation. Lix has a documented flakes feature freeze.
3. **Optional or lazy flake inputs do not exist** in any evaluator. Lix's feature freeze keeps them
   out. No solution may depend on a future arrival of one.
4. **Do not adopt a third-party lock aggregator.** The candidates are about one month old, single
   maintainer, and solve the mirror-image problem — they consume many flakes cheaply. They do not
   export a small library from a big flake.
5. **`flake = false` does not avoid a fetch.** It only skips that input's `flake.nix` and the
   recursion into its lock. It removes lock nodes, not fetches.

## The four open questions

These are the research agenda. Each needs a Lix-verified answer with quoted source.

### Q1 — do `follows` stanzas prevent lazy resolution?

Distinguish two cases, because they behave differently:

- **(a) a `follows` inside this repo's own `flake.nix`**, as a downstream adopter sees it;
- **(b) a `follows` or `--override-input` that the adopter writes against this repo's inputs.**

For each: does Lix fetch the affected input at lock time? Is the node still a lazy thunk at eval
time? Read `computeLocks` in `lix/libexpr/flake/flake.cc` and account for `hasOverride`,
`mustRefetch`, and `trustLock`.

Known partial answer, to confirm: case (b) forces a fetch, because an override takes the "creating
new input" branch instead of "keeping existing input". Also, if `flake.nix` and `flake.lock`
disagree about a `follows`, `mustRefetch` becomes true. That makes **lock drift** a real cost, and
it is the one path that can hand an adopter an SSH error.

### Q2 — relative paths and `git+file:` purity

Test the creator's position: plain Nix flakes do not support `git+file:` with a relative path.
devenv has a workaround. `$PWD` is impure, so it does not count.

Establish, on this Lix:

- does `git+file:.` work as an input URL in a plain `flake.nix`?
- does `path:../..`?
- why do this repo's current uses work — `devenv.yaml` uses `url: git+file:.` for
  `inputs.nix-configs`, and `checks/jj-experiments/devenv.nix` uses `url: path:../..`? devenv runs
  its own resolver (`devenv-nix-backend/bootstrap/resolve-lock.nix`) and links its own CppNix, so a
  devenv result does not transfer to plain Lix.

Method note: an earlier test used `git+file://$PWD?dir=…`. The shell expands `$PWD` before Nix sees
it, so that URL is absolute and **not** impure. But it also proves nothing about a `github:` URL.
Test the `github:` case explicitly.

### Q3 — does `?dir=<subdir>` work for a plain flake consumer?

Test the creator's position: `?dir=` does not solve anything inside a raw Nix flake.

Establish concretely:

1. A consumer declares a subflake at `<repo>/<subdir>/flake.nix` as
   `inputs.x.url = "github:owner/repo?dir=subdir"`. Does the consumer's lock hold only the
   subflake's inputs, or the root flake's too?
2. From inside that subflake, can `outputs` read files **above** its own root, such as
   `import ../../lib`? Test both a `github:` fetch and a `git+file:` fetch.
3. Does the subflake need its own `flake.lock`, and do the root `nix flake check` and
   `nix flake update` cover it?

One earlier measurement still needs the `github:` re-test. A
`git+file://…?dir=templates/terraform` metadata call resolved only that subflake's 5 inputs, and
the store path held the whole tree. If that holds for `github:` too, a subflake that exports only
`lib.kdn` takes an adopter's lock from ~106 nodes to ~4.

Also find real repos that ship a `?dir=` subflake as their public library entry point. Say whether
the pattern is common or rare. Rare would be a warning sign.

### Q4 — does any candidate depend on `lazy-trees`?

Consider these: `?dir=` subflakes, `follows` dedup, `flake = false`, `call-flake`, `npins`, and
`flake-compat`. State which of them work on Lix **today with no experimental features**. State
which do not.

## Two partial findings — treat as leads, not answers

A research pass started, then stopped early. It produced two grep-level facts. Both need a real
test before any conclusion rests on them.

1. **Lix 2.95.2 source holds zero `lazy-trees` references.** A source-wide search of the Lix tree in
   the store returned 0 hits. This agrees with settled item 2, and it adds source evidence to the
   warning message that item 2 already records.
2. **Lix rejects a relative path that leaves its parent store path.**
   `lix/libfetchers/path.cc:129` throws
   `relative path '%s' points outside of its parent's store path '%s'`. This is the exact error a
   `?dir=` subflake would hit when it reads `../../lib`, so it belongs to Q3 item 2. Find out which
   code paths reach line 129. Then find out whether a plain file read (`import ../../lib`) reaches
   it at all, or only an input resolution does. Do not conclude either way from the message text.

## Deliverable

A `.research.md` sibling, in the shape of
[jj-experiments-subset-check.research.md](../../jj-experiments-subset-check/research.md), with:

1. an answer to each of Q1-Q4, each tagged confirmed or unverified, with quoted source;
2. an honest ranked list of techniques that measurably reduce **(a)** this repo's own lock and eval
   cost, and **(b)** an adopter's cost. Rank by value against effort;
3. a plain statement if the answer is "very little, and here is why".

Only then decide whether to spike. If a spike happens, the likely shape is a subflake that exports
`lib.kdn` and the slot modules with three inputs. It also needs a second `flake.lock` in
`flake-update.sh` and in `checks`.

## Costs to record for any subflake spike

- A second `flake.lock` to maintain. It must not drift against the root's nixpkgs pin.
- The 4.1 MB whole-tree copy stays. That is what `lazy-trees` would fix and Lix will not ship.
- Lix's `trivial-flakes` behaviour: constrain the subflake's `flake.nix` to no function calls
  outside `outputs`, or transitive dependants break on older Lix.
