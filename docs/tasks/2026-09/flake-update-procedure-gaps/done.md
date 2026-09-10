---
type: Solution
description: How the flake update procedure gaps were repaired — a fetch step, a start-state table, a structural lock gate, and a repaired push hook.
task: definition.md
authored_by: agent
timestamp: 2026-09-09T20:00:00+02:00
---

# Repair the flake update procedure — solution

Task: [flake-update-procedure-gaps.md](definition.md).
Findings: [flake-update-procedure-gaps.research.md](research.md).

## Root cause analysis

Five root causes explain all 22 defects. Each one produced several symptoms.

### 1. The revset alias `fork` tags every descendant (D6)

`modules/slots/jj/fork/default.nix:84` holds this term:

```
(remote_bookmarks(remote="<fork-remote>") ~ upstream@<fork-remote>)::
```

The `::` suffix tags the fork main **and every descendant of it**. So
`upstream-chain = ~description("") & ~fork` can never hold a commit above the tree merge, and
`upstream-tip` always resolves **below** the merge. That single fact causes D2 (the documented
start state never matches) and O12. It also explains why the documented step 3 grafts the public
commit onto the wrong parent.

`upstream-safe = to-rebase & ~fork-direct` escapes this, because `fork-direct` tests **content**,
not topology. That is why the two aliases must never be swapped.

The follow-on rule: use `-B tree-merge`, never `-B fork-tip`. When a fork-only leaf sits above the
merge, `fork-tip` is that leaf. `-B fork-tip` then turns the leaf into a merge and leaves the tree
merge untouched.

### 2. No fetch, and no place to put one (D1)

The only fetch lived inside the `sync-upstream` alias, which runs at **push** time. So every
placement decision during an update read stale remote-tracking refs — measured at about 24 hours
stale. The docs had no step 0 at all, so there was nowhere for the operator to learn this.

### 3. A lock-file follows value is a path, not a node key (the jq defect)

An input value that is an **array** — for example `["nixpkgs-lib"]` — is a follows **path from the
root node**. It is not a node key. Any check that reads `.[0]` as a node key reports false
"dangling edge" hits. Measured on this repo's `flake.lock`: **3 false positives**
(`flake-parts_2`, `haumea`, `nixos-generators`, all resolving to `nixpkgs-lib`).

The same wrong assertion existed in `docs/flake-update.fork.md` and in the research file, so the
doc was corrected too.

### 4. Several shell checks failed open

- **`grep -q` under `pipefail`.** grep closes the pipe on the first match. The writer takes
  SIGPIPE, `pipefail` turns the pipeline into a failure, and the caller reads a match as "no
  match". Every `-q` was removed.
- **prek hands a pre-push hook no stdin** (`argc=0`). The old `while read` loop iterated zero
  times, so every check in `pre-push.sh` was inert.
- **An empty pattern list built `grep -i` with no `-e`.** That exits 2, which `if` reads as "no
  match", so the check passed silently. The patterns come from the git-ignored
  `devenv.slots.local.nix`, so a missing local file disabled the protection with no warning.
- **The remote guard was inverted** (O18a). Private content was blocked from the private fork and
  permitted to the public remote — the exact opposite of the option documentation.
- **`check-fork-contamination.sh` read the git index.** jj stages nothing, and `jj commit` fires no
  pre-commit hook, so the hook never triggered on the jj path.

### 5. `resolve-lock.nix` cannot read `"inputs": null` (D5)

`resolve-lock.nix:125` reads `node.inputs or { }`. The `or` operator answers a **missing**
attribute only, never a `null` value. A node with no inputs must **omit** the key. A strip step
that writes `null` produces a lock file that fails to evaluate.

One more hazard was measured while the work ran, and it belongs here (D4):

**Never redirect into the file a `jj` read is reading.** The shell opens a redirect before the
pipeline runs, so `jj file show -r <rev> x | … > x` finds `x` at 0 bytes. `jj file show` then
snapshots the empty file into `@`, and jj rebases that empty file into every descendant. Recovery
needs `jj op restore <op-before-the-snapshot>`. Measured on 2026-09-09 with `devenv.lock`.

## Solution

Eleven commits, all on the public chain, below the tree merge.

| Change | Commit |
|---|---|
| `docs(flake-update)`: fetch, start-state, strip and completion steps | `zwtpvztk` |
| `docs(jj)`: never redirect into the file a jj read is reading | `nslouuss` |
| `docs(rules/flake-update)`: the fetch, start-state and completion gates | `ptturzwt` |
| `docs(skills/flake-update)`: fix the dead links and add the missing gates | `wuttyzlx` |
| `feat(slots/jj)`: add the `fork-incoming` revset aliases | `yompknqn` |
| `feat(hack)`: add the fork flake update completion check | `txyzmvmt` |
| `fix(slots/jj)`: guard the public remote and check diff content, not only paths | `ypurxpxq` |
| `feat(slots/jj)`: show the update completion check before the public push | `knpopvtz` |
| `docs(tasks)`: record the denied-pattern gap for fork-only lock nodes | `rwwrqstw` |
| `docs(flake-update)`: add the fetch and reconcile step to the non-fork procedure | `oqyvntru` |
| `docs(jj)`: fix the follows-path assertion and add the redirect rule | `xtzurqnt` |

### Documents

- Both update docs and both rules now open with `jj git fetch --all-remotes`, and they name the
  reconcile branch. The fork doc gained a 5-state start-state table and the
  `jj rebase -r <safe-commit> -A upstream-tip -B tree-merge` form.
- Both skills were rewritten. Steps 0-9 now match the doc one to one (S6).
- Every relative `docs/…` link in both skills became a stable
  `https://github.com/nazarewk-iac/nix-configs/blob/main/docs/…` URL (S10). A slot installs a skill
  into a consumer repo, where a relative link is always dead.
- `.agents/rules/jujutsu-vcs.md` gained the redirect-hazard block quote.
- `docs/flake-update.fork.md` assertion 2 now checks the **string** form only, and it explains the
  follows-path mechanism and the 3 measured false positives.

### The structural gate — `hack/flake-update-complete.sh`

12 read-only assertions. It exits 1 on any FAIL. Remote names come from the environment at
runtime, so no private remote name appears in the file:

```bash
PUB="${KDN_PUBLIC_REMOTE:-kdn}"
FORK="${KDN_FORK_REMOTE:-$(jj config get git.push 2>/dev/null)}"
```

The shared jq prelude resolves a follows path recursively, which is the fix for root cause 3:

```bash
# shellcheck disable=SC2016  # $n and $root are jq variables, not shell variables
LOCK_JQ='
def res($n; $root; $v):
  if $v == null then "«missing»"
  elif ($v | type) == "string" then $v
  else reduce $v[] as $seg ($root; res($n; $root; ($n[.].inputs // {})[$seg]))
  end;
def edges($n; $root; $k):
  ($n[$k].inputs // {}) | [to_entries[] | res($n; $root; .value)];
'
```

Assertion 7 replaced the planned node-**count** assertion with a node **key-set** comparison
across the two chains. The key set is strictly stronger: a count can match while the wrong node
was dropped. It also needs **no pattern list at all**, so it catches a fork-only lock-node leak
that the pattern check misses today.

Assertion 6 must run before assertion 7: it proves the two lock files on the upstream tip differ
from `refs/remotes/$PUB/main`, which assertion 7 then reads as a real chain split.

**Assertions 2 and 3 test the tree merge, not `fork-tip`.** The first draft tested `fork-tip`, and
that was wrong. A fork-only fix legitimately sits above the merge, and `fork-tip` is then that
leaf, so the check rejected a correctly finished update. This is the same trap the docs name with
the `-B tree-merge`, never `-B fork-tip` rule. Assertion 3b keeps the old intent: the fork tip is
the merge itself, or a descendant of it (`fork-tip & tree-merge::`). The header line also prints
the tree merge now.

### Where the gate lives, and why

It is **not** a `checks/` derivation: it reads remote-tracking refs and the jj revset engine, so it
is impure by nature. It is **not** a git hook either, because `jj git push` fires none. So it ships
as a command:

- `jj-flake-update-complete` on `devenv.packages`
- the `jj update-check` alias
- an **advisory** call inside `sync-upstream`, printed before the y/n push prompt, bracketed by
  `--- flake update completion check (advisory) ---`

Advisory, not blocking, because `sync-upstream` also serves an ordinary push, where the
finished-update shape does not apply.

### The push path

`modules/slots/jj/pre-push.sh` was rewritten. It reads the remote name from `$1`, then
`PRE_COMMIT_REMOTE_NAME`, then a `PRE_COMMIT_REMOTE_URL`→name fallback. It fails loudly on an empty
pattern list (`KDN_JJ_PRE_PUSH_ALLOW_EMPTY=1` is the escape). It carries no `-q`. A new
`check_range()` takes revision arguments, so the zero sha never reaches `git diff`. It adds a
**diff-content** check on top of the path check. The no-stdin case fails closed for a public remote
(`KDN_JJ_PRE_PUSH_RANGE` is the escape) and warns-and-passes for the private one. It never prints
the pattern list.

`check-fork-contamination.sh` was kept but repaired: it reads `jj diff -r @` instead of the git
index, it carries no `-q`, it fails loudly on an empty list, and its header states plainly that
`jj commit` fires no pre-commit hook — so it is a net for the raw-git path only.

### New revset aliases

```nix
fork-incoming = "@..main@${cfg.fork.remote}";
fork-incoming-tip = "main@${cfg.fork.remote}";
```

They complete the pair with `upstream-incoming`. Step 0 reads both pairs after a fetch.

## Verification steps

| What | Command | Result |
|---|---|---|
| the completion check FAILs on an incomplete graph | `bash hack/flake-update-complete.sh` | 3 FAIL, 9 PASS, exit 1 before the operator split the update |
| the completion check PASSes on the finished graph | the same command, after the split and the assertion 2/3 fix | **21 PASS, 0 FAIL, exit 0** |
| read the exit code without a pipe | `… >/tmp/log 2>&1; echo $?` | a `\| tail` pipeline reports **tail's** status, so it printed 0 while the script exited 1 |
| the jq resolver has no false positives | baseline run on `flake.lock` | dangling 0, unreachable 0 |
| the resolver still detects a real fault | drop a referenced node | dangling 1 |
| the resolver still detects an unreachable node | drop a root edge | unreachable 1 |
| the script is tracked | `git ls-files -- hack/flake-update-complete.sh` | one line; `hack/.gitignore` gained `!/*.sh` |
| the new derivation evaluates | `devenv eval 'packages'` | holds `jj-flake-update-complete` |
| the shell builds on the fork chain | `devenv build shell` with `@` above `fork-tip` | exit 0 |
| the shell builds on the public chain | `devenv build shell` with `@` on `upstream-tip` | exit 0, `/nix/store/s91v65wcp47g3gs9kwyr8c8qnn6whiw3-devenv-shell` |
| every relative link resolves | link sweep over the 7 doc, rule and skill files | clean |

`devenv eval 'kdn.jj.config.aliases.update-check'` does **not** work — a slot option is not in the
devenv module set. Use `devenv eval 'packages'` instead.

## Follow-up notes

1. **Re-enter the devenv shell before you use the new commands.** The jj repo config is a symlink
   that devenv regenerates on `enterShell`
   (`~/.config/jj/repos/<id>/config.toml` → `/nix/store/…-jj-repo-config.toml`). The installed
   config has 0 hits for `fork-incoming`, so `jj log -r fork-incoming` and `jj update-check` fail
   until the shell restarts.
2. **One work item is deferred to the owner:**
   [fork-denied-patterns-miss-lock-nodes.md](../fork-denied-patterns-miss-lock-nodes/definition.md). The pattern
   list sits in the git-ignored `devenv.slots.local.nix`, whose content is itself a set of private
   strings. An agent must not read or print it, so an agent cannot verify a new pattern.
   Assertion 7 covers the class in the meantime.
3. **One exit criterion stays open.** Every nixos and darwin host must evaluate to a `drvPath` on
   both chains. It is testable today, because a finished graph exists. The other two criteria
   closed on 2026-09-09 — see the table in the task file.
4. **Nothing was pushed, and no bookmark moved.** `jj sync-remotes` reads the topology and moves
   both bookmarks. The user reviews and pushes.
