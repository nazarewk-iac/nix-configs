---
type: Task
description: The fork denied-pattern list does not match fork-only lock node keys, so the content check passes a commit that mixes private and public lock content.
status: open
authored_by: agent
timestamp: 2026-09-09T18:30:00+02:00
---

# The denied-pattern list misses fork-only lock nodes

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
| `jj fork-audit -q --color=never <that commit>` | "no fork-sensitive content found", exit **0** |
| the same commit in the `upstream-safe` revset | yes |

So a commit that genuinely mixes private and public lock content reads as clean, and the
revsets place it on the public chain.

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
2. Add the spelling those keys carry to `kdn.jj.fork.deniedFilePatterns` in
   `devenv.slots.local.nix`. Do not print the file.
3. Re-enter the devenv shell.
4. Confirm the check now catches it:
   ```bash
   jj fork-audit -q --color=never <that-commit>   # must exit 1
   ```
5. Re-check that `upstream-safe` no longer holds that commit.

## The interim cover

`hack/flake-update-complete.sh` assertion 7 compares node **key sets** across the two chains, so
it needs no pattern at all. It catches this class of leak today. Keep the pattern check as a
second net, never as the gate.
