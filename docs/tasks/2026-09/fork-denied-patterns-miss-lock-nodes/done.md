---
type: Solution
description: The owner added the private org pattern; the measurement shows a line-level check cannot see a value-only lock node update, so the structural assertion stays the gate.
task: fork-denied-patterns-miss-lock-nodes.md
status: done
authored_by: agent
timestamp: 2026-09-09T21:30:00+02:00
---

# The denied-pattern list and fork-only lock nodes — solution

Task: [fork-denied-patterns-miss-lock-nodes.md](definition.md).

## Root cause analysis

The task first stated one cause: the pattern list held no spelling that matches a fork-only lock
node key. That is true, and the owner fixed it. The measurement afterwards found a **second**
cause, and it is the one that matters.

### Cause 1 — the abbreviation and the full org name share no substring

The list already held an abbreviation of the private org, plus a host-name prefix. Neither can
match a lock node key, because the key spells the **full** org name. The two spellings share no
substring at all:

```
brew-tap--<org>--homebrew-tap | grep '<abbreviation>'  -> 0 matches
brew-tap--<org>--homebrew-tap | grep -i '<org>'        -> 1 match
```

So the fix is one entry: the private org segment. It covers all 4 private tap nodes, because the
segment is a prefix of the key's org field. Patterns expand as `glob-i`, so one lowercase entry
covers every casing.

The published public tree holds **0** occurrences of that segment, so the pattern cannot block the
public chain against itself. A pattern on `brew-tap` would: the public chain already declares 3
brew-tap nodes.

### Cause 2 — a line-level check cannot see a value-only node update

`fork-audit.sh` and the `fork-direct` revset both match **changed lines** (`diff_lines()`). A
flake update of an existing node changes only the `rev` and `narHash` lines inside that node. The
org name lives on the node **key** line and on the `owner` field, and an update leaves both
unchanged. So the org name appears only as diff **context**, which `diff_lines()` ignores by
design.

Measured on the current tree merge, the commit that carries the full locks:

| Measurement | Value |
|---|---|
| org-bearing lines in `jj diff -r tree-merge --git` | 12 |
| of those, **added** (`+`) | **0** |
| of those, **removed** (`-`) | **0** |
| of those, context | 12 |
| org-bearing lines in `jj file show -r tree-merge flake.lock` | 16 |
| `tree-merge & mutable()` | hit |
| `tree-merge & diff_lines(glob-i:*<segment>*)` | empty |
| `tree-merge & fork-direct` | empty |
| `jj fork-audit -q --color=never 'tree-merge'` | clean, exit 0 |

This is not a merge-commit artifact. The same holds for a single-parent commit that updates an
existing node. A merge is caught when it really changes an org-bearing line — one of the four
historical hits below is a merge.

## Solution

1. **The owner added one entry** to `kdn.jj.fork.deniedFilePatterns` in the git-ignored
   `devenv.slots.local.nix`: the private org segment. The literal string stays out of every tracked
   file, which is why that git-ignored file is its home.
2. **The devenv shell was re-entered**, so the generated jj repo config carries the new
   `fork-direct` terms.
3. **The task's verification step was corrected.** The old step asked for
   `jj fork-audit <the update commit>` to exit 1. That can never pass for a value-only update. The
   new step tests a commit that adds or renames a node.

No code changed. `fork-audit.sh` and `fork-direct` are correct for what they are — a line-level
content net. Making them read lock **structure** would duplicate
`hack/flake-update-complete.sh` assertion 7, which already does it and needs no pattern.

## Verification steps

| What | Command | Result |
|---|---|---|
| the pattern is live in the generated config | `grep -c -i '<segment>' "$(readlink -f "$(jj config path --repo)")"` | 2 (one `files()` term, one `diff_lines()` term) |
| the pattern catches a node **add or rename** | `jj log -r 'diff_lines(glob-i:*<segment>*) & files(flake.lock)'` | **4 commits**, one of them a merge |
| the pattern does **not** catch a value-only update | `jj log -r 'tree-merge & fork-direct'` | empty, as explained above |
| no false positive on the public chain | `jj fork-audit -q --color=never 'upstream-tip'` | clean, exit 0 |
| no false positive in published public history | `git grep -i '<segment>' refs/remotes/<public-remote>/main` | 0 hits |
| the structural gate still passes | `bash hack/flake-update-complete.sh` | 21 PASS, 0 FAIL, exit 0 |

## Follow-up notes

1. **Assertion 7 is the gate for lock content, and it stays that way.** It compares node key sets
   across the two chains, so it sees a value-only update and needs no pattern. Read the pattern
   check as a second net that catches a **new** private input.
2. **`fork-leaked` is non-empty in a normal finished update**, and that is correct. A fork-only fix
   above the tree merge matches `fork-direct` by design. The gate tests the intersection
   `fork-leaked & ::upstream-tip`, which must be empty.
3. **One tracked file changed with the pattern work:** the fork-only example slot settings file.
   It went onto the fork chain, never the public one.
