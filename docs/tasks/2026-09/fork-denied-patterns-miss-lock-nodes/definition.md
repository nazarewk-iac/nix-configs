---
type: Task
description: The fork denied-pattern list does not match fork-only lock node keys, so the content check passes a commit that mixes private and public lock content.
status: done
solution: fork-denied-patterns-miss-lock-nodes.done.md
authored_by: agent
timestamp: 2026-09-09T18:30:00+02:00
---

# The denied-pattern list misses fork-only lock nodes

> ✅ **Done** — see the solution in
> [fork-denied-patterns-miss-lock-nodes.done.md](done.md).
> The owner added the pattern on 2026-09-09. The measurement then showed the true cause is
> narrower than this file first stated: a line-level check cannot see a **value-only** lock
> node update at all.

Found while the flake update procedure gaps were repaired
([flake-update-procedure-gaps.md](../flake-update-procedure-gaps/definition.md)).

## The defect

`kdn.jj.fork.deniedFilePatterns` and `kdn.jj.fork.deniedMessagePatterns` feed three consumers:

| Consumer | Reads | Role |
|---|---|---|
| `modules/slots/jj/fork/fork-audit.sh` | file content at a revision | the content gate |
| `modules/slots/jj/pre-push.sh` | the pushed range | one net on the push path |
| `modules/slots/jj/fork/check-fork-contamination.sh` | `@` | one net for a raw `git commit` |
| `fork-direct` revset in `modules/slots/jj/fork/default.nix` | `files()` and `diff_lines()` | drives `fork-chain`, `upstream-safe`, `fork-leaked` |

None of them matches a fork-only **lock node key**. Measured on the previous update commit:

| Measurement | Value |
|---|---|
| lock nodes the commit changed | 45 |
| fork-only nodes in the commit's `flake.lock` | 5 |
| of those, changed in the commit | 4 |
| of the 5, **private** (need a pattern) | 4 |
| of the 5, public content that only the fork declares | 1 |
| `jj fork-audit -q --color=never <that commit>` | "no fork-sensitive content found", exit **0** |
| the same commit in the `upstream-safe` revset | yes |

So a commit that genuinely mixes private and public lock content reads as clean, and the
revsets place it on the public chain.

The 5 fork-only nodes are all homebrew tap inputs, and their node key spells the GitHub org.
Four keys carry the private org segment. One carries a public org, and the owner confirmed on
2026-09-09 that a public tap is fine to publish. So the pattern list needs **one** entry, the
private org segment — not one per tap.

A pattern on `brew-tap` alone is wrong. The public chain already holds 3 brew-tap nodes, so
that pattern would block the public chain against itself.

## Why it is deferred

The pattern list lives in `devenv.slots.local.nix`. Git ignores that file, and its content is
itself a set of private strings. An agent must not read or print it, so an agent cannot verify a
new pattern against the list. The owner must do this one.

## What the repair looks like

1. Read the fork-only node keys and their `url` fields:
   ```bash
   comm -23 \
     <(jj file show -r 'fork-tip' flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
     <(git show 'refs/remotes/kdn/main:flake.lock' | jq -r '.nodes[.root].inputs|keys[]' | sort)
   ```
   The command lists the root input names. Here they match the node keys one to one.
2. Add the private org segment from those keys to `kdn.jj.fork.deniedFilePatterns` in
   `devenv.slots.local.nix`. One entry covers all 4 private taps. Do not print the file, and do
   not put that string in a tracked file — `devenv.slots.local.nix` is git-ignored, which is why
   it is the right home. Skip the tap with the public org: it needs no pattern.
3. Re-enter the devenv shell.
4. Confirm the check catches a commit that **adds or renames** a private node:
   ```bash
   jj log -r 'diff_lines(glob-i:*<segment>*) & files(flake.lock)'   # must list commits
   ```
   Do **not** expect `jj fork-audit <the update commit>` to exit 1. A value-only update changes
   the `rev` and `narHash` lines, and the org name sits on the unchanged key line. The done file
   holds the measurement.
5. Re-check that `upstream-safe` no longer holds a commit that adds a private node.

## The interim cover

`hack/flake-update-complete.sh` assertion 7 compares node **key sets** across the two chains, so
it needs no pattern at all. It catches this class of leak today. Keep the pattern check as a
second net, never as the gate.

Assertion 7 measures chain **divergence**, not sensitivity. It flags the public tap too, because
the public `flake.nix` does not declare that input. That report is still correct: a lock node that
the flake does not declare is unreachable, and assertion 10 flags it as well. When the owner adds
a public tap to the public `flake.nix`, the node stops being fork-only and assertion 7 stops
flagging it. The script needs no change for that.
