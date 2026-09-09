---
type: Reference
description: Findings and the corrected fork flake update procedure, with a fetch step, a reconcile branch per start state, and a completion check.
status: open
authored_by: agent
timestamp: 2026-09-09T00:00:00+02:00
---

# Flake update procedure — gaps and the corrected procedure

## Question

Three defects in the flake update procedure are measured. Are they real? What else is
broken? What does the corrected procedure look like?

- **D1** — the procedure never tells the operator to fetch, and it has no reconcile step.
- **D2** — the documented start state is not the usual state.
- **D3** — there is no completion check, so an incomplete run looks finished.

## Verdict

All three defects are real. I confirmed each one against the current graph and the slot
source. I found 18 more defects (O1–O18). Two of them permit a silent private leak, and
one makes the documented step 3 command destructive in the usual start state.

The corrected procedure needs four additions:

1. A fetch and a reconcile step **before** the update, plus a second cheap fetch before
   the hand-off.
2. A start-state branch, with the work that each state needs first.
3. A precondition guard on the placement command (a mutable merge must exist).
4. A completion check with a structural leak gate that needs no pattern list.

Every claim below carries a **verified** tag with the command or the source line, or an
**unverified** tag. I ran no write command on this repo.

## Evidence base

- jj 0.44.0. Public remote `kdn`; the private remote is written `<fork-remote>` here.
- All measurements are read-only: `jj log`, `jj file show`, `jj op log`, `jj config list`,
  `git show`, `git ls-tree`, `jj fork-audit` (read-only by design).
- Change ids below are the live ones. Two local commits are fork-only, so this file names
  them by change id only.

Current graph, above the tree merge `xxxuyknszklq` (**verified**, `jj log -r 'to-rebase'`):

| change id | chain | note |
|---|---|---|
| `vtprpzrkvknv` | `upstream-safe` **and** `fork-tip` | `chore(flake): update` — the mixed update commit |
| `vzrtokzpmqvn` | `upstream-safe` | public docs work |
| `mzprwzwusxpn` | `upstream-safe` | public docs work |
| `rtsyynwvmoxr` | `upstream-safe` | public docs work |
| `sommnqortuuz` | `fork-leaked` | fork-only |
| `zrtvyyymtrns` | `fork-leaked` | fork-only |

`to-rebase` holds 6 commits; `upstream-safe` holds 4; `fork-leaked` holds 2
(**verified**). `@` is `zrytponuzysr`, it holds content, and it has one parent
(**verified**, `jj log -r '@' -T 'if(empty,"empty","content") ++ " " ++ parents.len()'`
prints `content 1`). The content in `@` belongs to other agents, not to the update.

## D1 — no fetch, and no reconcile step

### The gap is real

**verified.** A grep over `docs/flake-update.fork.md`, `docs/flake-update.md`,
`.agents/rules/flake-update.fork.md` and `.agents/rules/flake-update.md` finds no
`git fetch`, no `sync-upstream` and no `reconcile`. The only fetch sits inside the
`sync-upstream` alias, and that alias runs at push time.

**verified.** `nix run '.#update'` cannot fetch either. `flake-update.sh` runs
`nix flake update` and `python .flake.patches/update.py` only (lines 41 and 43).

**verified.** The last fetch ran on 2026-09-08 10:29 (`jj op log`, op `67425c53cc29`,
`fetch from git remote(s) kdn,<fork-remote>`). The current update commit `vtprpzrkvknv` was made on
2026-09-09. So the update resolved `upstream-tip`, `fork-tip` and `main@<fork-remote>`
against remote-tracking refs that were about 24 hours old.

**verified.** `jj log -r 'upstream-incoming'` prints nothing today. That result proves
nothing, because `upstream-incoming = @..main@<upstream-remote>` reads the same stale
remote-tracking ref. An empty incoming set is only meaningful right after a fetch.

### 1. The two aliases, quoted

Source: `modules/slots/jj/fork/default.nix`. Both aliases run through `bash -xeEuo
pipefail -c`, so any failure aborts the rest.

`sync-remotes`, lines 150–174:

```nix
      aliases.sync-remotes = [
        ...
        ''
          jj sync-upstream                                                     # 159
          fork_tip=$(jj log --no-graph -r 'fork-tip' -T 'change_id.short()')    # 160
          echo "Fork tip: $fork_tip"
          echo "Changes to push to ${cfg.fork.remote}:main (since main@${cfg.fork.remote}):"
          jj log -r "main@${cfg.fork.remote}..''${fork_tip}" --stat            # 163
          read -rp "Push ${cfg.fork.remote}:main? (y/n)" -n 1                   # 164
          echo
          if test "$REPLY" == y ; then
            jj bookmark set main -r "$fork_tip"                                 # 167
            jj git push --remote=${cfg.fork.remote} --bookmark=main             # 168
          else
            echo 'push cancelled'
            exit 1
          fi
        ''
      ];
```

`sync-upstream`, lines 175–200:

```nix
      aliases.sync-upstream = [
        ...
        ''
          jj git fetch --remote={${cfg.upstream.remote},${cfg.fork.remote}}     # 184
          tip=$(jj log --no-graph -r 'upstream-tip' -T 'change_id.short()')     # 185
          echo "Tip: $tip"
          echo "Changes to push to ${cfg.upstream.remote}:main (since main@${cfg.upstream.remote}):"
          jj log -r "main@${cfg.upstream.remote}..''${tip}" --stat              # 188
          read -rp "Push ${cfg.upstream.remote}:main? (y/n)" -n 1               # 189
          echo
          if test "$REPLY" == y ; then
            jj bookmark set upstream -r "$tip"                                  # 192
            git -C "$(jj root)" push ${cfg.upstream.remote} upstream:main       # 193
            jj git push --remote=${cfg.fork.remote} --bookmark=upstream         # 194
          else
            echo 'push cancelled'
            exit 1
          fi
        ''
      ];
```

Order of operations, `sync-upstream`: fetch both remotes → read `upstream-tip` → show the
range → prompt → move the `upstream` bookmark → push to the public remote with raw git →
push the `upstream` bookmark to the private remote.

Order of operations, `sync-remotes`: run all of `sync-upstream` first → read `fork-tip` →
show the range → prompt → move the `main` bookmark → push `main` to the private remote.

### Does `jj bookmark set` run before the push?

**Yes, in both aliases.** `sync-upstream` moves `upstream` on line 192 and pushes on line
193. `sync-remotes` moves `main` on line 167 and pushes on line 168 (**verified**, source
lines above).

State after a failed push:

| Failure | State that remains | Recovery |
|---|---|---|
| line 193 rejects the public push (non-fast-forward, or the network is down) | local `upstream` already points at the new tip. Line 194 never runs, because `-e` aborts. Local `upstream` now differs from `upstream@<fork-remote>`. | `jj op undo` reverts the bookmark move. Or read the old target from `jj op log` and set the bookmark back. Then reconcile and re-run `jj sync-upstream`. |
| line 194 fails after 193 succeeded | the public remote holds the commits; the private remote's `upstream` tracking bookmark lags | re-run `jj git push --remote=<fork-remote> --bookmark=upstream`. It is idempotent. |
| line 168 fails | local `main` already points at `fork-tip` and differs from `main@<fork-remote>`. The public side is **already published**, because line 159 ran first. | `jj op undo` for the bookmark, then re-run `jj sync-remotes`. The public push is not reversible. |

So the recovery is always available for the **local** state. The public push is not
reversible. This matters, because `sync-remotes` publishes the public chain **first**
(line 159) and the private chain last (line 168). A cancelled fork push leaves the public
side published.

**verified.** The op log shows the raw git push to the public remote leaves no jj
operation: on 2026-09-08 only `push bookmark upstream to git remote <fork-remote>` and
`push bookmark main to git remote <fork-remote>` appear. The public push at line 193 uses raw git, so jj
does not record it, and `jj op undo` cannot reach it.

### 2. Where must a fetch happen?

A fetch belongs in three places:

1. **Step 0, before the update.** Every placement decision reads a remote-tracking ref.
   A stale ref sends the public-inputs commit to the wrong parent, and the late fetch
   inside `sync-upstream` then rejects the push.
2. **Before the hand-off**, after the builds pass. The build phase can run for hours.
   A second `jj git fetch --all-remotes` plus one `jj log -r 'upstream-incoming'` costs
   seconds and turns a push rejection into a cheap reconcile.
3. **Inside `sync-upstream`**, where it already is. Keep it as the last guard.

Aliases whose value can change after a fetch (**verified** — I read every definition in
`modules/slots/jj/fork/default.nix` lines 59–123, and `jj config list --include-defaults`
for `immutable_heads()`):

| Alias | Changes after a fetch? | Why |
|---|---|---|
| `trunk()` | yes | `main@<fork-remote>` (line 60) |
| `immutable()` / `mutable()` | yes | `builtin_immutable_heads() = trunk() \| tags() \| untracked_remote_bookmarks()` |
| `fork` | yes | reads `remote_bookmarks(remote=<fork-remote>)` and `upstream@<fork-remote>` (lines 63–70) |
| `upstream-chain` / `fork-chain` | yes | both derive from `fork` (lines 78–79) |
| `upstream-tip` / `fork-tip` | yes | `latest()` over those chains (lines 80–81) |
| `pushed` / `pushed-fork` / `pushed-upstream` | yes | read `remote_bookmarks()` (lines 105–107) |
| `merge-frozen` | yes | `tree-merge & (immutable() \| pushed)` (line 115) |
| `upstream-incoming` / `upstream-incoming-tip` | yes | read `main@<upstream-remote>` (lines 89–90) |
| `upstream-local` | yes | reads `pushed-upstream` (line 122) |
| `tree-merge` | no | reads `::@` and `merges()` only (line 85) |
| `to-rebase` | no | `tree-merge..@ & ~description("")` (line 94) |
| `fork-direct` | no | a content predicate only (lines 71–77) |
| `upstream-safe` / `fork-leaked` | no | `to-rebase` intersected with `fork-direct` (lines 99, 111) |

Two consequences the docs do not state:

- A fetch that advances `main@<fork-remote>` moves `trunk()`, so commits that were mutable
  turn immutable. A placement command that needs a mutable `fork-tip` can stop to work
  between two steps of the same procedure.
- `fork-leaked` and `upstream-safe` are fetch-invariant. They are safe to read at any
  time. Every topology alias is not.

### 3. The reconcile step

Run the fetch, then read the two incoming sets. `upstream-incoming` exists.
A fork-side equivalent does not — add `fork-incoming = @..main@<fork-remote>` and
`fork-incoming-tip = main@<fork-remote>` to the slot, as a mirror of lines 89–90.

```bash
jj git fetch --all-remotes
jj log -r 'upstream-incoming' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r '@..main@<fork-remote>' -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
jj log -r 'merge-frozen'   # empty → the tree merge is mutable
```

| Outcome | Detection | Action |
|---|---|---|
| nothing moved | both incoming sets are empty | go on to the start-state branch. No rebase. |
| the public tip moved | `upstream-incoming` is not empty | integrate the public tip **before** the update, so the new locks resolve against the new public base. Mutable tree merge: `jj rebase -s 'roots(upstream-local)' -d 'upstream-incoming-tip'`. Frozen tree merge (`merge-frozen` not empty): `jj new fork-tip upstream-incoming-tip -m 'chore(upstream): merge'`, then `jj new` for an empty `@`. |
| the fork tip moved | `@..main@<fork-remote>` is not empty | the fetched fork commits are immutable, because `trunk()` is `main@<fork-remote>`. Build forward: `jj new fork-tip 'main@<fork-remote>' -m 'chore(fork): merge fork main'`, then `jj new`. |
| both moved | both sets are not empty | do the public integration first, then the fork merge forward. Re-read `merge-frozen` and `fork-leaked` after each step. |

**A rebase is genuinely required in one case only:** the public tip moved **and** the tree
merge is still mutable. That is a real topology fix, which
`.agents/rules/jujutsu-vcs.md` permits. Every other outcome builds forward with `jj new`,
and needs no rebase.

The mutable rebase form and the frozen build-forward form are both documented at
`docs/jujutsu-vcs.fork.md:138-146`, with the proof at
`checks/jj-experiments/test_rebase.md` (**verified** by reading; I did not run the test).
The fork-side build-forward form is a mirror of the public one — **unverified**, no test
covers a moved fork tip.

### 4. Is a fetch safe with content in `@`?

Yes for the content, with one process hazard.

- jj takes a snapshot of the working copy before it runs a command that reads `@`. The op
  log shows the snapshot ops, for example `bd8ad4a0141e` "snapshot working copy"
  (**verified** from `jj op log`; I did not run a fetch in this pass). So the uncommitted
  content becomes part of `@` and the fetch does not discard it.
- `jj git fetch` moves remote-tracking refs. It does not change `@`'s parents, and it does
  not change `@`'s content (**unverified** — not executed here).
- It can abandon local commits that the remote rewrote (**unverified** — standard jj
  behavior, not executed here).
- **Process hazard:** the snapshot writes the repo. When several agents write files in the
  same working copy, that snapshot races them. This repo already recorded file truncation
  from such a race (`.agents/rules/jujutsu-vcs.md`). So fetch when you own the working
  copy, and not in parallel with another writer.

## D2 — the documented start state is not the usual state

### The gap is real

**verified.** `docs/flake-update.fork.md:83` and `:120` both assume `@` is an empty change
with `main` and `upstream` as parents. `.agents/rules/flake-update.fork.md:46` and
`.agents/skills/flake-update-fork/SKILL.md:24` repeat it.

**verified.** `docs/jujutsu-vcs.fork.md:31-50` states the opposite resting shape: `@` is a
single-parent empty change on the merge, and the dual-parent `@` is correct in one place
only, right after a publish. `.agents/rules/jujutsu-vcs.md` also tells the operator to
keep `@` on parked work. So the update's assumed start state exists only in the minutes
after a publish.

**verified, and this is the sharp point.** Every local commit above the tree merge is
`fork`-tagged, because the `fork` alias tags every descendant of the fork `main` for
topology reasons (lines 68–69). Measurements: `to-rebase` = 6, `to-rebase & fork` = 6,
`to-rebase & upstream-chain` = 0. `upstream-chain = ~description("") & ~fork` (line 78),
so `upstream-tip = latest(upstream-chain)` **cannot** be a commit above the merge. Today
`upstream-tip` is `wonzvknwzrwm`, which sits **below** the tree merge (**verified**,
`jj log -r 'upstream-tip'` and `jj log -r 'upstream-local'`).

Consequence for the documented step 3
(`jj new --insert-after upstream-tip --insert-before fork-tip`, `docs/flake-update.fork.md:159`):

- `-A upstream-tip` grafts the public-inputs commit **below the tree merge**, onto the
  pre-merge public chain.
- `-B fork-tip` adds it as an extra parent of `fork-tip`, and keeps the current parent.
  `checks/jj-experiments/test_placement.md:42-45` proves that `-B` adds a parent and keeps
  the old one (**verified** by reading the proof doc).
- `fork-tip` is `vtprpzrkvknv`, a single-parent, mutable, non-merge commit (**verified**,
  `parents.len()` = 1). So the **mixed update commit itself** turns into the merge.
- The four `upstream-safe` commits stay `fork`-tagged. They can never reach the public
  remote. `sync-upstream` cannot see them, because `upstream-tip` never selects them.

So the documented topology does not form, and the public docs work is marooned on the fork
chain. This consequence is **unverified by execution** — I derived it from the proven `-B`
semantics and from the measured alias values. I ran no write command.

### 5. The real start states

| # | Start state | Detection | First step |
|---|---|---|---|
| i | `@` empty, two parents, right after `jj sync-remotes` | `jj log -r '@' -T 'if(empty,"empty","content") ++ " " ++ parents.len()'` prints `empty 2`; `to-rebase` is empty | fetch, reconcile, then run the update. This is the documented path. |
| ii | `@` empty on a linear stack of local commits | prints `empty 1`; `to-rebase` is not empty; `fork-tip & merges()` is empty | **work first:** route or publish the stack, so the two-chain shape exists. Then update. |
| iii | `@` holds content | prints `content …` | **work first:** route the content out of `@` with the mixed-working-copy recipe (`checks/jj-experiments/test_placement.md:120-131`). Leave `@` empty. Never mix that content with the update. |
| iv | local commits mix `upstream-safe` and fork-only, safe above fork-only | `jj log -r 'fork-leaked & ::upstream-safe'` is not empty | **work first:** reorder, see below. Then update. |
| v | `@` empty, one parent, `to-rebase` empty, the tree merge is frozen | prints `empty 1`; `to-rebase` empty; `merge-frozen` not empty | fetch, reconcile, then update. Step 3b must manufacture a mutable merge. |

**The current state is (iii) and (iv) together, with the update already run.**
`@` holds content and has one parent. `fork-leaked & ::upstream-safe` returns
`sommnqortuuz` and `zrtvyyymtrns`, so two fork-only commits sit below four
`upstream-safe` commits. `fork-tip` is the mixed update commit, not a merge
(**verified**, all four commands above).

States (ii), (iii) and (iv) need work **before** the update starts. States (i) and (v) do
not.

### 7. Case (iv), the hard one

**Consequence.** An `upstream-safe` commit that sits above a fork-only commit cannot reach
the public remote, because its ancestry holds the fork-only commit. The topology
alias makes this worse: all six local commits are `fork`-tagged, so `upstream-tip` never
selects any of them and `sync-upstream` never offers them. The commits are content-clean
and still invisible. They stay on the fork chain for ever until somebody reorders them.

**Reorder before the update, not after.** Three reasons:

1. The update's placement step reads `upstream-tip` and `fork-tip`. Both give a wrong
   answer while the stack is linear (measured above). A correct placement needs the
   two-chain shape first.
2. The update commit must be the newest fork-side commit. A reorder after the update has
   to rewrite it, and it holds the mixed locks.
3. A reorder before the update touches only mutable, unpublished commits.

Safest correction sequence, oldest safe commit first:

```bash
# 0. fetch and reconcile first (see D1). @ must be empty; route any content out first.

# 1. manufacture a mutable merge above the stack, if fork-tip is not already one:
jj log -r 'fork-tip & merges() & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'      # only when the line above prints nothing

# 2. move each upstream-safe commit onto the public chain, oldest first:
jj rebase -r <safe-commit> -A upstream-tip -B fork-tip
#    re-read upstream-tip and fork-tip after every move — both change

# 3. verify:
jj log -r 'to-rebase'         # only the fork-only commits stay above the merge
jj log -r 'fork-leaked'       # only intended fork leaves
jj fork-audit -q              # no fork content on the upstream chain
```

Command 1 is the proven frozen-tree step (`checks/jj-experiments/test_placement.md:36-54`,
**verified** by reading). Command 2 is the same placement with `jj rebase` instead of
`jj split`, because the content is already in a commit. `jj rebase` accepts `-A` and `-B`
in jj 0.44 (**verified**, `jj rebase --help` lines 249 and 254). The repeat over several
commits is **unverified** — no test in `checks/jj-experiments/` covers it.

An operator who does not want a rebase has one alternative: publish the stack to the
private remote only, and defer the public contribution. That keeps the public docs work
unpublished, so it is a worse outcome.

## D3 — the completion check

### The gap is real

**verified.** No file states a completion condition. `docs/flake-update.fork.md:209-215`
prints three values and asks the operator to "confirm". It never asserts that two commits
exist, that the fork tip is a merge, or that the public chain received the update.

**verified.** Today exactly one commit exists: `chore(flake): update` on the fork chain.
`upstream-tip`'s `flake.lock` and `devenv.lock` are **byte-identical** to
`refs/remotes/kdn/main`, so the public chain holds no update at all (`jj file show -r
upstream-tip <lock> | cmp -s - <(git show refs/remotes/kdn/main:<lock>)` succeeds for both
files).

### 8. The completion check, as runnable commands

Save as `hack/flake-update-complete.sh`, or paste into a shell. `PUB` is the public
remote. `FORK` is the private one.

```bash
#!/usr/bin/env bash
# Completion check for one fork flake update. Read-only. Exit 1 on any FAIL.
set -uo pipefail
PUB=kdn
FORK='<fork-remote>'
fail=0
ck() { if [ "$2" = pass ]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }
nz() { [ -n "$(jj log -r "$1" --no-graph -T '"x"')" ]; }

ft=$(jj log -r 'fork-tip'     --no-graph -T 'change_id.short()')
ut=$(jj log -r 'upstream-tip' --no-graph -T 'change_id.short()')
echo "fork-tip=$ft  upstream-tip=$ut"

# 1. two commits exist, one per chain
{ [ -n "$ft" ] && [ -n "$ut" ] && [ "$ft" != "$ut" ]; } && r=pass || r=fail
ck "two tips, one per chain, and they differ" "$r"

# 2. the fork tip is a merge with exactly two parents
#    SUPERSEDED — do not copy assertions 2 and 3 from here. They must test `tree-merge`, because a
#    fork-only fix legitimately sits above the merge and `fork-tip` is then that leaf. The shipped
#    version is `hack/flake-update-complete.sh`.
[ "$(jj log -r 'fork-tip' --no-graph -T 'parents.len()')" = 2 ] && r=pass || r=fail
ck "fork tip is a merge with two parents" "$r"

# 3. one parent is the upstream tip
nz 'parents(fork-tip) & upstream-tip' && r=pass || r=fail
ck "the upstream tip is a parent of the fork tip" "$r"

# 4. the second parent carries the published fork main (fast-forward precondition)
nz "main@$FORK & ::fork-tip" && r=pass || r=fail
ck "the published fork main stays an ancestor of the fork tip" "$r"

# 5. the published public main stays an ancestor of the upstream tip
nz "main@$PUB & ::upstream-tip" && r=pass || r=fail
ck "the published public main stays an ancestor of the upstream tip" "$r"

# 6. the upstream commit really changed both locks — run this BEFORE check 7
for f in flake.lock devenv.lock; do
  if jj file show -r 'upstream-tip' "$f" | cmp -s - <(git show "refs/remotes/$PUB/main:$f"); then r=fail; else r=pass; fi
  ck "$f on the upstream tip differs from the public remote" "$r"
done

# 7. no fork-only lock node in the upstream commit — the structural leak gate
for f in flake.lock devenv.lock; do
  n=$(comm -12 \
        <(jj file show -r 'upstream-tip' "$f" | jq -r '.nodes|keys[]' | sort) \
        <(comm -23 <(jj file show -r 'fork-tip' "$f" | jq -r '.nodes|keys[]' | sort) \
                   <(git show "refs/remotes/$PUB/main:$f" | jq -r '.nodes|keys[]' | sort)) \
      | wc -l | tr -d ' ')
  [ "$n" = 0 ] && r=pass || r=fail
  ck "$f on the upstream tip holds no fork-only node ($n found)" "$r"
done

# 8. no dangling input edge in either lock of the upstream commit
for f in flake.lock devenv.lock; do
  d=$(jj file show -r 'upstream-tip' "$f" | jq -r '.nodes as $n | [ .nodes|to_entries[]|.key as $o
    | (.value.inputs//{})|to_entries[] | (.value|if type=="array" then .[0] else . end) as $t
    | select($n[$t]==null) | "\($o)->\($t)" ] | length')
  [ "$d" = 0 ] && r=pass || r=fail
  ck "$f on the upstream tip has no dangling input edge ($d found)" "$r"
done

# 9. @ is empty with a single parent
[ "$(jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len()')" = "empty 1" ] && r=pass || r=fail
ck "@ is empty with one parent" "$r"

# 10. no fork content below the upstream tip
nz 'fork-leaked & ::upstream-tip' && r=fail || r=pass
ck "no fork-leaked commit is an ancestor of the upstream tip" "$r"

exit "$fail"
```

Expected output in the finished state: `PASS` on every line, exit 0.

Expected output in the **current** state (**verified**, I ran each assertion by hand):

```
fork-tip=vtprpzrkvknv  upstream-tip=wonzvknwzrwm
PASS  two tips, one per chain, and they differ
FAIL  fork tip is a merge with two parents            # parents.len() = 1
FAIL  the upstream tip is a parent of the fork tip    # it is only an ancestor
FAIL  flake.lock on the upstream tip differs from the public remote
FAIL  devenv.lock on the upstream tip differs from the public remote
FAIL  @ is empty with one parent                      # prints "content 1"
```

Two design notes come out of these measurements:

- **Assertion 1 alone is worthless.** The two tips already differ today, and the public
  chain still holds no update. Assertion 6 is the one that catches D3.
- **Assertion 7 must run after assertion 6.** With no upstream commit, assertion 7 counts
  0 fork-only nodes and passes for the wrong reason (**verified** — it printed 0 for both
  locks in the current, incomplete state).

### 9. A content-level leak check for the upstream commit

The name-only hook cannot do this (`modules/slots/jj/pre-push.sh:69` greps
`git diff --name-only`). A content-level check already exists as a tool:
`jj fork-audit` greps the file **content** at a revision
(`modules/slots/jj/fork/fork-audit.sh:148`, `jj file show -r "$c" "$f" | grep -nIiF`) and
the diff as a fallback (line 160). It reads the pattern list from its own baked
`SENSITIVE_FILE_PATTERNS`, so the operator never types or prints a private string.

Run it as a gate, always with `-q`, so it prints no pattern:

```bash
jj fork-audit -q --color=never 'upstream-tip' || echo 'FAIL: denied pattern in the upstream commit'
```

**Measured limit, and it is severe.** The current pattern list does not match the lock
content. `jj fork-audit -q --color=never vtprpzrkvknv` prints "no fork-sensitive content
found" and exits **0** (**verified**), even though that commit changes 4 of the 5 fork-only
lock nodes. The same result comes out of the revsets: `vtprpzrkvknv` is inside
`upstream-safe`, so it is `~fork-direct` (**verified**).

Measured lock content of the current update commit `vtprpzrkvknv`:

| Measurement | Value |
|---|---|
| lock nodes changed in the commit | 45 |
| fork-only `brew-tap--*` nodes in the commit's `flake.lock` | 5 |
| of those, changed in the commit | 4 |
| `brew-tap--*` nodes on `refs/remotes/kdn/main` | 3 |
| fork root inputs vs public root inputs | 60 vs 55 |
| fork-only root inputs that do **not** match `^brew-tap--` | 0 |

So the commit genuinely mixes public and private lock content, and the split is mandatory.

**Conclusion.** A pattern-based check cannot be the gate for lock content today. The gate
must be **structural** — assertion 7 above, which needs no pattern at all. Keep the
pattern check as a second net, and fix the pattern list as a separate work item: add the
spelling that appears in the fork-only lock node keys and their `url` fields to
`kdn.jj.fork.deniedFilePatterns`, then confirm with
`jj fork-audit -q --color=never vtprpzrkvknv` that it exits 1.

An alternative form that reads the configured list without a print, for an operator who
wants a raw grep:

```bash
umask 077; devenv eval 'kdn.jj.fork.deniedFilePatterns' > /tmp/pats.txt   # prints nothing to the terminal
# then grep each pattern from the file against the two locks, and report the file name only
rm -f /tmp/pats.txt
```

The `devenv eval` output format for a list is **unverified** — I ran no devenv command.
Prefer `jj fork-audit -q`.

## 10. Other defects

| # | File and line | Defect | Corrected text |
|---|---|---|---|
| O1 | `docs/flake-update.md:22-30` | Claims the update makes a chain on top of `upstream`, and that `@` sits on top of `upstream`. False in a fork repo. | Add a guard: "This procedure applies when `kdn.jj.fork.enable = false`. In a fork repo use [flake-update.fork.md](../../flake-update.fork.md), which overrides every step below." |
| O2 | `docs/flake-update.md:41-42,77,99`; `.agents/rules/flake-update.md:22-23,26,52-53` | Tells the operator to run `jj bookmark set upstream`. The fork rule forbids it. | Same guard as O1, plus one line: "In a fork repo `jj sync-remotes` moves every bookmark. Never run `jj bookmark set`." |
| O3 | `docs/flake-update.md:114`; `.agents/rules/flake-update.md:33`; `.agents/skills/flake-update/SKILL.md:42` | The non-fork files use `upstream@<fork-remote>` as the pre-update anchor. A non-fork repo has no fork remote. | Use `main@<public-remote>`. |
| O4 | `.agents/rules/flake-update.md:9,11,13` | Links are relative to the repo root, so they resolve to `.agents/rules/docs/…`. All three are broken (**verified** with a file test). | `../../docs/flake-update.md`, `../../docs/flake-update.fork.md`, `../../docs/jujutsu-vcs.md`, `jujutsu-vcs.md`. |
| O5 | `.agents/skills/flake-update/SKILL.md:8,9,10` | `../../docs/…` resolves to `.agents/docs/…`. All three broken (**verified**). | `../../../docs/…`. |
| O6 | `.agents/skills/flake-update-fork/SKILL.md:8` | `../../../../docs/…` resolves above the repo root. Broken (**verified**). | `../../../docs/flake-update.fork.md`. |
| O7 | `docs/flake-update.fork.md:9-11` | Claims this file is installed as `.claude/rules/flake-update.fork.md`. The slot installs `.agents/rules/flake-update.fork.md` (`modules/slots/jj/fork/default.nix:233-234`). | "The agent rule `.agents/rules/flake-update.fork.md` is installed as `.claude/rules/flake-update.fork.md` by the `kdn.jj.fork` slot. This file is the full doc it points to." |
| O8 | `docs/flake-update.fork.md:227` | The verify loop hardcodes `flake.lock` inside a `for f in flake.lock devenv.lock` loop. | Use `"$f"`. |
| O9 | `docs/flake-update.fork.md:99-106,185-192`; `.agents/skills/flake-update-fork/SKILL.md:39-46` | The strip list hardcodes `^brew-tap--`. A fork-only input with another name leaks in silence. Today all 5 fork-only root inputs match the prefix, so the defect is latent (**verified**). | Derive the set with no prefix filter: `comm -23 <(fork root inputs) <(public root inputs)`, then strip those node keys and their input edges. |
| O10 | `docs/flake-update.fork.md:185-193` | No check that `STRIP` is not empty. When `flake-lock-merge` writes nothing, the `jq` transform is a no-op and every fork node stays in the public `devenv.lock`. | Add `test "$STRIP" != '[]' \|\| { echo 'FAIL: empty strip list'; exit 1; }`. |
| O11 | `docs/flake-update.fork.md:82-112` | The quick summary omits the patch-file move that the same file documents at 248-258 and the skill lists as step 4. This cycle changes `.flake.patches/config.toml` and one `.patch` file (**verified**), so the omission bites now. | Add `jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/` to the quick summary, with the note that a lock-only update skips it. |
| O12 | `docs/flake-update.fork.md:95,159`; `.agents/rules/flake-update.fork.md:52`; `.agents/skills/flake-update-fork/SKILL.md:35` | The insert command needs `fork-tip` to be a **mutable merge**. There is no precondition and no branch for a frozen or non-merge `fork-tip`. | Add the guard from `docs/jujutsu-vcs.fork.md:112`: when `fork-tip & merges() & mutable()` is empty, first run `jj new --no-edit -B @ -m 'chore(upstream): merge'`. |
| O13 | `docs/flake-update.fork.md:209-215` | "Verify the topology" prints values and asserts nothing. | Replace with the completion check from § 8. |
| O14 | `docs/flake-update.md:66-71` | The patch branch assumes the patch landed upstream. No branch for another failure cause. The decision procedure lives only in `.agents/skills/flake-update/SKILL.md:27-36`. | Point at `docs/flake-patches.md` and the `flake-patches` skill, and keep one branch per cause. |
| O15 | `docs/flake-update.fork.md:399-408` | The test section states no order and no gate. | State that the NixOS build of `upstream-tip` gates the public push, and that the Darwin build of `fork-tip` gates the private push. |
| O16 | `docs/flake-update.fork.md` (whole file) | Never mentions `jj fork-audit`, although `.agents/rules/flake-update.fork.md:63` requires it. | Add `jj fork-audit -q --color=never 'upstream-tip'` to the verify step. |
| O17 | `modules/slots/jj/fork/default.nix:159,168` — not documented anywhere | The two pushes are not atomic, and `sync-remotes` publishes the **public** chain first. A cancelled fork push leaves the public side published. | Add a warning to `docs/flake-update.fork.md`: run the completion check and both builds **before** `jj sync-remotes`, because the public push is not reversible. |
| O18 | `modules/slots/jj/pre-push.sh:10,65-67,69`; `modules/slots/jj/fork/check-fork-contamination.sh:23,42,51` | Four code defects, out of scope for the doc edits. See below. | Separate commits. |

**O18 runtime behavior is now measured.** Tested on 2026-09-09 in throwaway repos under `/tmp`
(isolated `HOME`, `JJ_CONFIG`, `GIT_CONFIG_GLOBAL=/dev/null`; jj 0.44.0, prek 0.5.2). The full
record lives in
[generalization-001-slots-sharing-readiness.md](../generalization/001-slots-sharing-readiness/definition.md)
§ "the guard is inert three ways over". Summary:

- **`jj git push` fires no `.git/hooks/pre-push`, and `jj commit` fires no `.git/hooks/pre-commit`.**
  A native hook that exits 1 blocked a raw `git push` and did not block either jj command.
  **verified.** This confirms O18d, and it widens it: the fork pushes at `fork/default.nix:168,194`
  run no check either.
- **prek hands the `pre-push` hook no stdin.** A probe hook got `argc=0` and an empty stdin, while a
  native hook on the same push got `argc=2` and one ref line. **verified.** So `pre-push.sh:42`
  iterates zero times and **every** check inside the loop never runs — including the always-on
  blocked-message check.
- **`push_remote` resolves to `refs`.** With `argc=0`, line 10 falls back to
  `${PRE_COMMIT_REMOTE_BRANCH%%/*}`, and prek sets `PRE_COMMIT_REMOTE_BRANCH=refs/heads/main`.
  **verified.** This confirms O18b: the correct variable is `PRE_COMMIT_REMOTE_NAME`, which the
  script never reads.

Net: the hook passes everything on every remote, for three independent reasons. O18a is the third
reason, not the first.

O18 in detail (all **verified at source level**; runtime behavior measured as above):

- **O18a — the gate is inverted.** `pre-push.sh:65-67` skips the sensitive-path check
  unless the push goes to the **private** remote. `modules/slots/jj/default.nix:54`
  documents the opposite: "blocked from pushing to non-fork remotes". So the public push
  gets no file check, and the private push gets one it does not need. This is the worst
  defect I found.
- **O18b — the remote name is read from the wrong variable.** `pre-push.sh:10` uses
  `${PRE_COMMIT_REMOTE_BRANCH%%/*}`. The pre-commit framework sets that variable to a
  branch ref, not a remote name; `PRE_COMMIT_REMOTE_NAME` holds the remote name. So
  `push_remote` is very likely never equal to the configured remote, and the
  remote-specific checks never run.
- **O18c — the zero sha reaches `git diff`.** Line 48 builds a `range` variable for the
  new-branch case, but line 69 passes `$remote_sha` to `git diff` unchanged. On a new
  branch that is the zero sha, `git diff` fails, and `set -e` aborts the push.
- **O18d — the content check is dead in a jj workflow.**
  `check-fork-contamination.sh` does grep content (lines 42 and 51), but it runs at the
  `pre-commit` stage and reads the **git index** (`--cached`). jj never runs git hooks and
  does not keep the index in sync with `@`. Line 23 also skips any `@` that is in
  `fork-chain`, and all six local commits are `fork`-tagged today (**verified**).

## 11. Skill divergences

| # | Divergence |
|---|---|
| S1 | `.agents/skills/flake-update/SKILL.md:20-21` keeps `jj bookmark set upstream -r @-` with no fork guard. Same as O2. |
| S2 | `.agents/skills/flake-update/SKILL.md:8-10` — three broken links. Same as O5. |
| S3 | `.agents/skills/flake-update/SKILL.md:42` uses `upstream@<fork-remote>` in the non-fork skill. Same as O3. |
| S4 | The patch decision procedure exists only in `.agents/skills/flake-update/SKILL.md:27-36`. `docs/flake-update.md:66-71` holds a shorter, different version. The skill is richer than the doc it points to. |
| S5 | `.agents/skills/flake-update-fork/SKILL.md:8` — broken link depth. Same as O6. |
| S6 | Step numbers diverge. The skill numbers the patch move as step 4 (`:51-52`); the doc puts it in a separate section (`docs:248-258`) and omits it from the quick summary. The skill's note "the `jq` transform (step 2)" (`:137`) points at its own step 2; the doc calls the same thing step 3 (`docs:275`). |
| S7 | The graph drawings differ. `.agents/skills/flake-update-fork/SKILL.md:66-67` lists `main@<fork-remote>` and `upstream@<fork-remote>` as two rows with no edge marks. `docs/flake-update.fork.md:58-60` draws the second `├─╮`. `.agents/rules/flake-update.fork.md:28-34` omits the `upstream@<fork-remote>` row. Three drawings of one topology. |
| S8 | No skill and no rule mentions a fetch, a reconcile, or a completion check. D1 and D3 apply to all six files. |
| S9 | No skill states the mutable-merge precondition for the insert command. Same as O12. |
| S10 | Both skills link into `docs/…`. The slots install them into a consumer repo (`modules/slots/nix/default.nix:91-92`, `modules/slots/jj/fork/default.nix:235-236`), where `docs/` does not exist. Every link is dead in every consumer. |
| S11 | `.agents/skills/flake-update/SKILL.md:9` points at the fork **doc**, and never names the `flake-update-fork` **skill**, which is the artifact the fork slot installs. |
| S12 | `.agents/rules/flake-update.md:17-27` omits `devenv update`, which `docs/flake-update.md:58-60` and both skills require. A lock-only update from the rule alone leaves `devenv.lock` stale. |

`if(immutable, "PUSHED", "not pushed")` in `.agents/skills/flake-update-fork/SKILL.md:76`
and `docs/flake-update.fork.md:306` works as written (**verified**, I ran the template).

## The corrected procedure

Steps 0 to 3b are new. Steps 4 to 8 keep the current mechanics with the fixes above.

### Step 0 — fetch, then reconcile

```bash
jj git fetch --all-remotes
jj log -r 'upstream-incoming'          # public commits not in the local tree
jj log -r '@..main@<fork-remote>'      # fork commits not in the local tree
jj log -r 'merge-frozen'               # empty → the tree merge is mutable
```

Apply the reconcile table in § 3. Do not go on while either incoming set is not empty.

### Step 1 — name the start state, and fix it

Run the three detection commands from § 5:

```bash
jj log -r '@' --no-graph -T 'if(empty,"empty","content") ++ " " ++ parents.len() ++ "\n"'
jj log -r 'to-rebase' --no-graph -T 'change_id.short() ++ "\n"'
jj log -r 'fork-leaked & ::upstream-safe' --no-graph -T 'change_id.short() ++ "\n"'
```

- `content …` → route the content out of `@` first (state iii).
- `to-rebase` not empty and `fork-tip` not a merge → publish or route the stack (state ii).
- `fork-leaked & ::upstream-safe` not empty → reorder first (state iv, § 7).

Start the update only from state (i) or state (v).

### Step 2 — run the update

```bash
nix run '.#update'
devenv update
```

A patch failure has its own branch — see `docs/flake-patches.md`.

### Step 3 — carve the full locks into a fork-side commit

```bash
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
FORK_UPDATE=$(jj log -r @- --no-graph -T 'change_id.short()')
```

### Step 3b — make sure a mutable merge exists (new)

```bash
jj log -r 'fork-tip & merges() & mutable()' --no-graph -T '"exists\n"'
jj new --no-edit -B @ -m 'chore(upstream): merge'     # only when the line above prints nothing
```

From state (i) the split already made a mutable merge, so this step does nothing. From
state (v) it manufactures one. This is the proven step
(`checks/jj-experiments/test_placement.md:36-54`).

### Step 4 — insert the public-inputs commit

```bash
jj new -A upstream-tip -B fork-tip -m 'chore(flake): update (public inputs)'
PRE_UPDATE_REV=$(jj log -r 'upstream@<fork-remote>' --no-graph -T 'commit_id')
nix run "git+file://$PWD?rev=${PRE_UPDATE_REV}#flake-lock-merge" -- "$FORK_UPDATE"
```

`flake-lock-merge` reads the reference lock from the given revision and runs
`nix flake lock --reference-lock-file` (**verified**,
`packages/flake-lock-merge/flake_lock_merge/cli.py`). That Nix command always writes
`./flake.lock`, so `@` must be the public-inputs commit. The `--path` flag only picks the
path to **read** in the jj tree; it does not redirect the output (**verified** from the
same file).

### Step 5 — strip the fork nodes from `devenv.lock`, with no prefix filter (fix O9, O10)

```bash
STRIP=$(comm -23 \
  <(jj file show -r "$FORK_UPDATE" flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  <(jj file show -r @               flake.lock | jq -r '.nodes[.root].inputs|keys[]' | sort) \
  | jq -R . | jq -sc .)
test "$STRIP" != '[]' || { echo 'FAIL: empty strip list — did flake-lock-merge run?'; exit 1; }
jj file show -r "$FORK_UPDATE" devenv.lock | jq --argjson strip "$STRIP" '
  .nodes |= with_entries(select(.key as $k | ($strip|index($k))|not))
  | .nodes |= map_values(if .inputs then .inputs |= with_entries(select((.value|tostring) as $t|($strip|index($t))|not)) else . end)
' | jq -j '.' > devenv.lock
```

### Step 6 — move the patch files down (fix O11)

```bash
jj squash --from "$FORK_UPDATE" --into upstream-tip -- .flake.patches/
```

A lock-only update skips this step. This cycle needs it (**verified** — the update commit
touches `.flake.patches/config.toml` and one `.patch` file).

### Step 7 — park an empty `@`

```bash
jj new fork-tip
```

### Step 8 — check, build, fetch again, hand off

```bash
bash hack/flake-update-complete.sh          # § 8, every line must PASS
jj fork-audit -q --color=never 'upstream-tip'
# build the public chain on a NixOS host — this gates the public push
./nixos-rebuild.sh build remote=<hostname>
# build the fork chain on the macOS machine — this gates the private push
nix run '.#darwin-rebuild' -- build
jj git fetch --all-remotes && jj log -r 'upstream-incoming'   # must stay empty
```

Then hand off. The user runs `jj sync-remotes`. Never run `jj bookmark set`. Remember that
`sync-remotes` publishes the public chain first, and that push is not reversible (O17).

## Unverified claims, collected

- The exact result of `jj new -A upstream-tip -B fork-tip` in the current start state. I
  derived it from the proven `-B` semantics in `checks/jj-experiments/test_placement.md`
  and from the measured alias values. I ran no write command.
- `jj rebase -r <c> -A upstream-tip -B fork-tip`, repeated over several commits. The flags
  exist in jj 0.44; no test covers this use.
- The fork-side build-forward form `jj new fork-tip 'main@<fork-remote>'`. It mirrors the
  proven public form; no test covers a moved fork tip.
- What `jj git fetch` does to `@`'s content and to obsolete local commits. Fetch is
  forbidden in this pass.
- Git's rejection of a non-fast-forward push at `sync-upstream:193`. Standard git
  behavior, not executed here.
- Every runtime claim about `pre-push.sh` and `check-fork-contamination.sh` (O18). Source
  level only; no push and no commit ran.
- The `devenv eval` output format for a list option in § 9.
