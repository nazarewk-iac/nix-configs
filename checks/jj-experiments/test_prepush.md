---
type: Reference
description: What the jj pre-push hook blocks, per remote, proven by test_prepush.py; also its three fail-safe rules and two known limits.
timestamp: 2026-09-10T07:00:00+02:00
authored_by: agent
---

# The pre-push guard: which remote may receive private content

The hook is `hack/pre-push.sh`. The fork slot bakes the pattern
lists into it (`modules/slots/jj/fork/default.nix`, `runtimeEnv`). The
executable proof is `test_prepush.py`.

## The rule, in one line

Private content may reach the **private fork remote** only. Every other remote
gets the content checks. One check is stricter: an always-blocked commit message
stops a push to **every** remote, the fork included.

| Case | public remote | private fork remote | Test |
|---|---|---|---|
| A path matches a file pattern | blocked | permitted | `test_public_remote_blocks_a_sensitive_path`, `test_private_remote_permits_a_sensitive_path` |
| A commit message matches a message pattern | blocked | permitted | `test_public_remote_blocks_a_sensitive_message` |
| A diff line matches a file pattern | blocked | permitted | `test_public_remote_blocks_a_sensitive_line_in_a_public_path` |
| A commit message matches an always-blocked pattern | blocked | blocked | `test_always_blocked_message_stops_both_remotes` |
| Nothing matches | permitted | permitted | `test_a_clean_commit_passes_on_both_remotes` |

The direction is easy to invert by accident, and an inverted guard reads as
"working" — it still blocks something, just the wrong remote. So the first two
rows are the load-bearing cases of this group.

A path check alone is not enough. A file with a public name can hold a private
string, so the hook also greps the range diff. That is why row 3 exists.

## Three fail-safe rules

1. **An empty pattern list is a defect, not a permission.** The lists come from
   the git-ignored `devenv.slots.local.nix`. When that file is absent, the hook
   would build `grep -i` with no `-e`, which exits 2 — and `if` reads that as
   "no match", so every check would pass in silence. The hook fails loudly
   instead, and names the file to restore
   (`test_an_empty_pattern_list_fails_loudly`). `KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1`
   is the explicit escape hatch
   (`test_an_empty_pattern_list_has_an_explicit_escape_hatch`).
2. **An unknown remote is public.** With no argv and no `PRE_COMMIT_*` variable
   the hook cannot name the remote, so it applies the content checks
   (`test_an_unknown_remote_is_treated_as_public`).
3. **No ref lines is a failure for a public remote.** prek hands a pre-push
   hook no stdin (measured: argc=0, empty stdin), so the hook cannot tell what
   moves. It fails closed for a public remote
   (`test_no_ref_lines_fails_closed_for_a_public_remote`) and warns for the
   private one (`test_no_ref_lines_passes_for_the_private_remote`).
   `KDN_JJ_PRE_PUSH_RANGE='<range>'` names the range by hand
   (`test_a_named_range_replaces_the_missing_stdin`).

## Never pass a zero sha to git as a revision

git writes one line per ref: `<local ref> <local sha> <remote ref> <remote
sha>`. A **new** ref carries a zero remote sha, and a **delete** carries a zero
local sha.

- A new ref has no range. `git diff <zero-sha> <sha>` fails on that input, so
  the hook asks git for the commits the target remote does not hold yet:
  `<local sha> --not --remotes=<remote>`
  (`test_a_new_ref_checks_the_commits_the_remote_lacks`,
  `test_a_new_ref_of_a_clean_commit_passes`).
- `main..<local sha>` would be wrong here: it is empty when the pushed branch
  **is** `main`.

## Two known limits

1. **A delete-only push to a public remote fails closed.** A zero local sha
   means no new content, so the hook skips the line — and then it has seen no
   ref at all, so it takes the no-stdin path and refuses. That is safe but it is
   a false positive (`test_a_delete_only_push_falls_back_to_the_no_stdin_path`).
2. **This group tests the script, not the wrapper.** The suite runs
   `pre-push.sh` and bakes its own pattern lists, because
   `writeShellApplication` exports `runtimeEnv` inside the wrapper and a caller
   cannot override it. The `devenv` slot target is a `deferredModule`, so the
   wrapper's store path is unreachable without a full module evaluation. So one
   line stays unproven here: `entry = lib.getExe prePushHook` in
   `modules/slots/jj/fork/default.nix`.

## The larger limit: jj fires no git hook

`jj git push` runs no `.git/hooks/pre-push` (measured). The hook runs on a real
`git push`, which `jj sync-upstream` uses for the public push. So treat the hook
as one net, not the gate. `jj fork-audit` is the content gate.

## How the tests reach the script

The three entry points export `KDN_JJ_PRE_PUSH_SH`:
`checks/default.nix` (the flake check), `checks/jj-experiments/devenv.nix` (the
interactive shell), and `subset-runner.nix`. All three read it from
`render-fork-config.nix`, which returns `{ toml, prePush }`. A bare `pytest` run
with no slot skips this group, the same way `harness.slot_config()` skips.

Every pattern in the group is a `PLACEHOLDER-*` string. No real sensitive term
appears in the suite.
