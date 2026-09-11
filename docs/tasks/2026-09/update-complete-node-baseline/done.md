---
type: Solution
description: Assertion 7 now defines a fork-only node by reachability over public-named edges, so a new public input passes and a private input still fails.
timestamp: 2026-09-12T01:00:00Z
authored_by: agent
---

# Solution

## Root cause analysis

Assertion 7 read the **already-pushed** public lock (`refs/remotes/<public>/main:<lock>`) as its
definition of public content. That file is a snapshot from before the current update. Every node
the update adds to the public lock is absent from it, so the assertion classed each one as
private, then found it in the public lock and failed.

The set the assertion built was "new since the last public push". The set it needed was "private".

The correct baseline sits in the lock the assertion already reads: `nodes.root.inputs` of the
upstream lock is the list of inputs the public flake declares.

Measured on 2026-09-12 for node `den`:

| Term | Value |
|---|---|
| in the already-pushed public lock | false |
| in the fork-tip lock | true |
| in the upstream-tip lock | true |
| declared as an input by the public flake | **true** |

The first three rows put `den` in the flagged set. The fourth row shows it is public.

## Solution

`hack/flake-update-complete.sh` gained a `FORK_ONLY_JQ` program, and assertion 7 now uses it.

A node is **fork-only** when the public-named edge graph cannot reach it from the root of the fork
lock. An edge `(node k, input name)` counts as **public-named** when the public lock declares that
same input name at that same node `k`.

Two properties follow:

- A brand-new public input is public-named at once, so it never flags. No maintenance, and no
  allowlist of node names.
- The rule applies at every node, not at the root only. `devenv.lock` needs that: its root inputs
  match on both chains, and the private taps enter one level down, under the repository's own node.

## Verification steps

Run the check:

```bash
bash hack/flake-update-complete.sh
```

Assertions 7a and 7b report `(0 found)` and pass. 21 of 22 assertions pass; the remaining failure
is `@ is empty with one parent`, which reports the working copy, not the locks.

Three measurements taken on the real locks on 2026-09-12:

| Case | Old rule | New rule |
|---|---|---|
| the real public lock | 2 flagged (false) | **0 flagged** |
| the private tap inputs, in `flake.lock` and in `devenv.lock` | flagged | **5 flagged, both files** |
| a private tap forged into a copy of the public lock, node only | flagged | **1 flagged** |

The forged case is the negative test. It also fails assertion 10, so two independent assertions
catch it.

## Follow-up notes

One leak shape passes both lock assertions: a forged node that also carries its root edge. The
lock then declares the input as public, and no lock-level rule can tell it apart from a real
public input. That shape needs a private input name inside the public `flake.nix`, which is plain
text in a new public commit. `jj fork-audit` matches it, and a probe on 2026-09-12 confirmed the
denied-pattern list matches the private organization string. The comment above assertion 7 records
this limit.
