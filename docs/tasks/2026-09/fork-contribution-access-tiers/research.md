---
type: Reference
description: Evidence on what each fork procedure assumes about push access, plus one designed contribution procedure per access tier.
status: open
authored_by: agent
timestamp: 2026-09-09T00:00:00+02:00
---

# Contribution by access tier — findings and designed procedures

Task file: [fork-contribution-access-tiers.md](definition.md).

Every claim below carries a tag. **verified** names the command or the source line.
**unverified** means I did not run the test. A wrong "verified" tag is worse than an honest
"unverified".

This pass was read-only. It changed no procedure file.

## Placeholders and privacy

- `<fork-remote>` / `<private-remote>` — the private fork remote name.
- `<upstream-remote>` — the public remote. Its name in this repo is `kdn`.
- `refs/remotes/kdn/main` — the public git ref. `upstream@<fork-remote>` is the jj anchor for the
  last synced public point.
- `hosts/anji` is the public Darwin example host.
- This file names no private host, no private path, and no denied pattern. The fork's
  denied-pattern list lives in the git-ignored local slot settings file. Those patterns are
  themselves private strings.

## Method

Read in full: `modules/slots/jj/fork/default.nix`, `modules/slots/jj/default.nix`,
`modules/slots/jj/pre-push.sh`, `modules/slots/jj/fork/fork-audit.sh`,
`modules/slots/jj/fork/check-fork-contamination.sh`, `docs/flake-update.fork.md`,
`docs/flake-update.md`, `docs/jujutsu-vcs.fork.md`, `docs/jujutsu-vcs.md`,
`docs/generalization-plan.md`, `docs/tasks/generalization-001-slots-sharing-readiness.md`,
`docs/tasks/README.md`, `devenv.nix`, and the pointer files under `.agents/rules/`.

Ran read-only commands only: `jj log`, `jj diff --name-only`, `jj file show`, `jj config list`,
`jj bookmark list`, `jj fork-audit`, `jj duplicate --help`, `jj workspace list`, `git remote -v`,
`git ls-tree`, `git show`, `git config --get-regexp`.

---

## A. What the current procedures assume

### A1. The fork slot inventory

Source: `modules/slots/jj/fork/default.nix`. All line numbers below come from that file.
**verified** by a full read.

Every revset alias and every command emits only when `cfg.enable && cfg.fork.enable` holds
(line 50). **verified.**

#### Repo-level git defaults

| Setting | Value | Line | Access needed |
|---|---|---|---|
| `git.push` | the fork remote | 53 | fork push |
| `git.fetch` | fork remote, then public remote | 54-57 | fetch on both |

**verified** at run time: `jj config list` reports `git.push = "<fork-remote>"` and
`git.fetch = ["<fork-remote>", "kdn"]`.

So a bare `jj git push` targets the private fork. That default is the collaborator's friend.

#### Revset aliases

| Alias | Line | Reads | Writes | Push access |
|---|---|---|---|---|
| `trunk()` | 60 | fork remote ref | — | none |
| `fork` | 63-70 | fork remote refs, content, messages | — | none |
| `fork-direct` | 71-77 | file paths, diff lines, messages | — | none |
| `upstream-chain` / `fork-chain` | 78-79 | local graph, `fork` | — | none |
| `upstream-tip` / `fork-tip` | 80-81 | the two chains, by commit time | — | none |
| `tree-merge` | 85 | local graph | — | none |
| `upstream-incoming` / `upstream-incoming-tip` | 89-90 | **public remote ref** | — | none, but needs the public remote to exist locally |
| `to-rebase` | 94 | local graph | — | none |
| `upstream-safe` | 99 | `to-rebase`, `fork-direct` | — | none |
| `pushed` / `pushed-fork` / `pushed-upstream` | 105-107 | remote refs | — | none |
| `fork-leaked` | 111 | `to-rebase`, `fork-direct` | — | none |
| `merge-frozen` | 115 | `tree-merge`, `immutable()`, `pushed` | — | none |
| `upstream-local` | 122 | `pushed-upstream`, `tree-merge` | — | none |

Every alias is read-only. Two of them (`upstream-incoming`, `upstream-incoming-tip`) name
`main@<upstream-remote>`, so they fail when the public remote is absent from the local repo.
**verified** by a source read of lines 89-90.

#### Commands

| Command | Line | Reads | Writes | Push access needed |
|---|---|---|---|---|
| `jj fork-audit` | 124-129 | local commits, the denied patterns | nothing | **none** |
| `jj fork-help` | 130-149 | `docs/jujutsu-vcs.fork.md` in the store | nothing | **none** |
| `jj sync-upstream` | 175-200 | both remotes | **public `main`**, fork `upstream` | **both remotes** |
| `jj sync-remotes` | 150-174 | both remotes | public `main`, fork `upstream`, fork `main` | **both remotes** |
| pre-commit hook `jj-check-fork-contamination` | 212-220 | git index | nothing | none |
| pre-push hook `jj-pre-push` | 223-230 | the push range | nothing | none |

**verified** by a source read.

### A2. `jj sync-remotes` moves bookmarks first, and pushes second

Exact order, from the source. `jj sync-remotes` runs under `bash -xeEuo pipefail` (lines 155-157),
so the first non-zero exit aborts it. **verified.**

1. Line 159 — `jj sync-upstream`. The public half runs **first**.
2. Line 184 — `jj git fetch --remote={<upstream-remote>,<fork-remote>}`.
3. Line 185 — resolve `upstream-tip`.
4. Lines 187-189 — print the range, then prompt.
5. Line 192 — `jj bookmark set upstream -r "$tip"`. A **local** bookmark move, before any push.
6. Line 193 — `git -C "$(jj root)" push <upstream-remote> upstream:main`. The **public** push.
7. Line 194 — `jj git push --remote=<fork-remote> --bookmark=upstream`.
8. Line 160 — back in `sync-remotes`, resolve `fork-tip`.
9. Line 167 — `jj bookmark set main -r "$fork_tip"`.
10. Line 168 — `jj git push --remote=<fork-remote> --bookmark=main`.

Quoted source, step 5 and step 6:

```bash
            jj bookmark set upstream -r "$tip"
            git -C "$(jj root)" push ${cfg.upstream.remote} upstream:main
            jj git push --remote=${cfg.fork.remote} --bookmark=upstream
```

**What happens when the public push is denied.** **verified** by the source order and by
`set -e`:

- The local `upstream` bookmark has already moved (line 192).
- The public remote is unchanged.
- Line 194 never runs, so `upstream@<fork-remote>` is unchanged.
- `sync-upstream` exits non-zero, so `sync-remotes` aborts at line 159. `main` never moves and
  the fork `main` is never pushed.

So the answer to "does it move bookmarks first, push second" is **yes**, and the failure is
**partial**: a local bookmark move with no push behind it.

**Is the partial failure recoverable?** Yes, but only with a command a non-maintainer must never
run. `jj bookmark set` refuses a backward move without `--allow-backwards`
(`docs/jujutsu-vcs.md:349`, **verified** by a read). The clean repair is `jj undo` or
`jj op restore`. Neither route appears in any procedure doc. **verified** — I grepped and read all
five procedure files and found no recovery step for a denied push.

A second hazard: the local `upstream` bookmark now sits ahead of `upstream@<fork-remote>`. A later
`jj git push --remote=<fork-remote> --bookmark=upstream` would publish a fork-side view of
`upstream` that the public remote never received. **verified** by the source; the effect is a
reasoned consequence, so treat the consequence as **unverified** in practice.

### A3. Procedure → assumed tier → what a reader without the access hits

| Procedure (file:line) | Assumed tier | What a reader without that access hits |
|---|---|---|
| `docs/flake-update.fork.md:32` — "The user runs `jj sync-remotes` manually to place the bookmarks and push" | maintainer | The one publish step in the whole file. No alternative exists. |
| `docs/flake-update.fork.md:25-33` — "NEVER move bookmarks by hand … `jj sync-remotes` moves both" | maintainer | The reader is told not to move a bookmark, and the only sanctioned mover needs public push access. A dead end. |
| `docs/flake-update.fork.md:111` — "NEVER run `jj bookmark set` — `jj sync-remotes` does that" | maintainer | Same dead end, restated in the quick summary. |
| `docs/flake-update.fork.md:232-244` — "After `jj sync-remotes`, stack new work" | maintainer | A collaborator's tree never reaches that state, so the one correct dual-parent `@` never becomes available. |
| `docs/flake-update.fork.md:368-373` — "Confirm before the user pushes" | maintainer | The verify step exists; the push step does not. |
| `docs/flake-update.md:42` and `:77` — `jj bookmark set upstream -r @-` | maintainer | The fork-free base doc moves the public bookmark directly, with no privacy gate at all. |
| `docs/flake-update.md:114` — `jj log -r 'upstream@<fork-remote>'` | maintainer | The base doc, which claims to be fork-free, reads a fork remote ref. A reader with no fork gets an unresolvable revset. |
| `docs/jujutsu-vcs.fork.md:172` — "Bookmarks are moved by `jj sync-remotes`, not by hand" | maintainer | Same dead end as above. |
| `docs/jujutsu-vcs.fork.md:35-44` — the topology diagram | maintainer | The diagram shows one person who owns both chains. It offers no shape for a queued change. |
| `docs/jujutsu-vcs.fork.md:46-50` — "Right after you publish (`jj sync-remotes`)" | maintainer | The reader cannot publish, so the paragraph does not apply. |
| `docs/jujutsu-vcs.md:102-103` — "'Never push' (the repo rule) is for agents. The push recipes here are for the maintainer to run." | maintainer | The only place in the docs that names a role. It names exactly one. |
| `docs/jujutsu-vcs.md:440-444` — "Safe default — push a feature/PR branch, never over the primary" | any | The closest thing to a collaborator recipe. It names no remote tier and no privacy gate, so a reader can aim it at the public remote. |
| `.agents/rules/flake-update.fork.md:8-9` — "The user runs `jj sync-remotes` and pushes" | maintainer | One user. |
| `.agents/rules/jujutsu-vcs.md` — "**NEVER push changes** — the user reviews and pushes" | maintainer | One user. |
| `docs/generalization-plan.md:210` — "Any push. The creator reviews and pushes." | maintainer | One creator. |

**verified** — each row comes from a direct read of the named line.

### A4. Measured hazard: the tip aliases point somewhere else than the docs assume

The placement golden path is `jj split -A upstream-tip -B fork-tip …`
(`docs/jujutsu-vcs.fork.md:114`). It assumes `fork-tip` **is** the tree merge.

Current tree, **verified** with `jj log -r '<alias>'`:

| Alias | Resolves to |
|---|---|
| `tree-merge` | `xxxuyknszklq` `chore(upstream): merge` |
| `fork-tip` | `vtprpzrkvknv` `chore(flake): update` — the **top** of the local stack, six commits above the merge |
| `upstream-tip` | `wonzvknwzrwm` `fix(kdn-ssh-access): …` — **below** the merge |
| `fork-chain` | all six local commits above the merge |
| `upstream-chain` | seven commits below the merge |

Cause, **verified** by a source read of lines 63-70 and 78-81: `fork` folds in the topology term
`(remote_bookmarks(remote="<fork-remote>") ~ upstream@<fork-remote>)::`, so every descendant of
the fork `main` counts as fork-side. `fork-chain = ~description("") & fork` therefore claims all
six local commits, including the three upstream-safe documentation commits.
`upstream-chain = ~description("") & ~fork` excludes them, so `upstream-tip` falls back to a
commit below the merge.

Two consequences:

1. `jj split -A upstream-tip -B fork-tip` today inserts a commit below the merge and re-parents
   the top of the local stack onto it. That is not the documented intent. **verified** by the tip
   values; the exact resulting graph is **unverified**, because I did not run the command.
2. `jj sync-remotes` would set `upstream` to a commit below the merge. So the three upstream-safe
   documentation commits above the merge would **not** reach the public remote. `upstream-safe`
   names them, but no command consumes `upstream-safe`. **verified** by the alias values and by a
   source read of lines 150-200 — no command reads `upstream-safe`.

Consequence 2 is the core defect for change type (d). An upstream-safe change authored above the
merge is silently not published.

### A5. The pre-push hook and the two given defects

`modules/slots/jj/pre-push.sh`. The hook assumes that **the person who pushes to the private fork
is the only person who can leak**. Its whole remote-specific block runs for that one remote.

```bash
  # Remote protection: only applies when pushing to the private fork remote
  if test "$push_remote" != "$PRIVATE_REMOTE"; then
    continue
  fi
```

Recorded as given, not re-derived:

- **Defect 1 — the guard at `pre-push.sh:64-67` is inverted.** It skips the denied-file and
  denied-message checks for every remote **except** the private fork. Private content is blocked
  from the fork and permitted to the public remote.
- **Defect 2 — the file check at `pre-push.sh:69` greps `git diff --name-only`.** It matches file
  names only, never file content. A lock file that holds private organisation names passes.

`docs/tasks/generalization-001-slots-sharing-readiness.md:17-52` holds the reproduction and two
further defects (an ignored `$range`, and an empty pattern list that passes silently).
**verified** by a read of that file.

**Which tier does each defect hurt most?**

- **Defect 1 hurts the fork collaborator most.** The maintainer is the only person the current
  procedures let push publicly, and the maintainer splits content by hand and knows the topology.
  A collaborator who reaches for a public remote at all — a personal GitHub fork, for example —
  gets **zero** content protection on exactly that push. The outside contributor is unaffected;
  they never hold the fork content.
- **Defect 2 hurts anybody who pushes a lock file, and the collaborator worst.** Measured
  evidence below.

**Composite finding — now measured, not reasoned.** In the sanctioned publish path, **no push runs
a working denied-content check.**

**Defect 3 — `jj` fires no git hook.** Measured on 2026-09-09 in a throwaway colocated repo under
`/tmp`, with an isolated `HOME`, `JJ_CONFIG`, and `GIT_CONFIG_GLOBAL=/dev/null`, on jj 0.44.0. The
repo held an executable `.git/hooks/pre-push` and `.git/hooks/pre-commit`. Each hook printed a
marker and exited 1.

| Command | Hook marker | Exit | Effect |
|---|---|---|---|
| `jj git push --remote=origin --bookmark=main` | **absent** | **0** | the remote gained `refs/heads/main` |
| `git push origin main` (control) | **present** | **1** | git refused the push |
| `jj commit -m …` | **absent** | **0** | jj created the commit |

**verified.** So:

- The fork pushes at `fork/default.nix:168` and `:194` use `jj git push`. They run **no** check.
  The "private content is blocked from the fork" half of defect 1 never operated.
- The public push at `fork/default.nix:193` uses raw `git push`, so it is the **only** push in the
  whole procedure that reaches the hook. Defect 1 then skips every check for exactly that remote.

Read those two points together: the one push that reaches the guard is the one push the guard
refuses to inspect. Enforcement today is zero, on every remote.

- **`check-fork-contamination.sh` is dead code.** It greps content
  (`git diff --cached | grep -qi`, lines 50-57), so it would catch defect 2's blind spot. But
  `fork/default.nix:217` installs it as a **pre-commit** hook, and jj fires no pre-commit hook
  (row 3 above). This repo commits through jj. So the one content-aware check never runs.
  **verified.**

**Defects 4 and 5 — measured in the same pass.** Both hooks install through devenv `git-hooks`,
which is **prek** 0.5.2, not python pre-commit.

- **Defect 4 — prek forwards no stdin.** A probe hook at the `pre-push` stage received `argc=0` and
  an empty stdin, while a native `.git/hooks/pre-push` on the same push received `argc=2` and one
  ref line. `pre-push.sh:42` reads its ref lines from stdin, so the loop iterates **zero** times.
  Every check inside it never runs, including the always-on blocked-message check. **verified.**
- **Defect 5 — `push_remote` is always `refs`.** With `argc=0`, `pre-push.sh:10` falls back to
  `${PRE_COMMIT_REMOTE_BRANCH%%/*}`, and prek sets `PRE_COMMIT_REMOTE_BRANCH=refs/heads/main`. The
  variable that holds the remote name is `PRE_COMMIT_REMOTE_NAME`, and the script never reads it.
  **verified.**

So the comparison at lines 64-67 is never equal, for the fork remote either. Defect 1 is the third
reason the guard passes everything, not the first. The full record, with the measured output, is in
[generalization-001-slots-sharing-readiness.md](../generalization/001-slots-sharing-readiness/definition.md).

**Design consequence for checkpoint 001.** A fix to defect 1 alone restores enforcement on the
public raw-`git push` only. Every `jj git push` stays unchecked, including a collaborator's push to
a personal public GitHub fork. jj offers no hook mechanism, so the check cannot live in
`.git/hooks/` for a jj-driven push. It must move into a **wrapper command** — a jj alias that runs
the check and then pushes — or into `pre-push.sh` invoked by that alias. Record this before anybody
implements the defect-1 one-liner, because the one-liner alone does not close the hole.

**Why a collaborator who does not know the topology is the worst-affected person.** Three reasons
compound:

1. The one guard that would catch their mistake is disabled on the exact remote they would leak
   to (defect 1).
2. The guard they do get is name-based, so it cannot see the private strings that matter
   (defect 2).
3. No document tells them that a full `flake.lock` on the fork chain is private content. The fork
   procedure splits the lock in two (`docs/flake-update.fork.md:63-77`), but it explains the split
   as a build concern, not as a privacy boundary.

---

## B. Role vocabulary

| Role | Push access | Sends changes through |
|---|---|---|
| **maintainer** | the public remote **and** the private fork | direct push, `jj sync-remotes` |
| **fork collaborator** | the private fork only | a queue bookmark on the private fork |
| **outside contributor** | neither | a pull request against the public repo |

The evidence needed no fourth contributor role. One refinement: the fork collaborator splits into
two states — a collaborator with the local slot settings file present, who holds the fork aliases
and the `sync-remotes` footgun, and one without it, who holds neither. § H covers both.

**Reconciliation with `external adopter`.** `docs/generalization-plan.md:10,37` defines an
external adopter as anybody but this repo's creator, and their repo as the adopter repo. An
adopter *consumes* the modules in their own repo and sends nothing back; a contributor *sends
changes back* to this repo, and needs no adopter repo at all.

---

## C. Procedures per role and change type

### C1. maintainer

| Change type | Command sequence |
|---|---|
| (a) upstream-safe | `jj log -r 'merge-frozen'` (empty → the merge is mutable) · `jj split -A upstream-tip -B fork-tip -m 'feat(...): generic' -- <files>` · on a frozen tree first `jj new --no-edit -B @ -m 'chore(upstream): merge'` · `jj fork-audit 'upstream-safe'` · `jj log -r 'fork-leaked'` · `jj sync-remotes` |
| (b) fork-only | `jj split -m 'feat(fork): ...' -- <files>` · `jj sync-remotes` |
| (c) flake update | `docs/flake-update.fork.md` steps 1-6, then `jj sync-remotes` |
| (d) upstream-safe on top of fork work | § C4 |

Source for (a) and (b): `docs/jujutsu-vcs.fork.md:106-136`. **verified** by a read. Read § A4
first: the two tip aliases do not resolve where that recipe assumes.

### C2. fork collaborator

The design goal: the collaborator never touches `main` and never touches `upstream`. They create
their own bookmark namespace and push it to the private fork only.

**(a) an upstream-safe change**

```bash
jj git fetch --remote=<fork-remote> --remote=<upstream-remote>

# work in @, then carve the change out:
jj split -m 'docs(...): description' -- <files>
SAFE=$(jj log -r @- --no-graph -T 'change_id.short()')

# prove it is upstream-safe — see § E. jj fork-audit alone is NOT enough:
jj fork-audit "$SAFE"

# lift the change onto the published public anchor, with no damage to the fork chain:
jj duplicate "$SAFE" --onto 'upstream@<fork-remote>'
# read the new change id from the "Duplicated <old> as <new>" line that jj prints

jj bookmark create 'upstream-queue/<name>/<slug>' -r <new-change-id>
jj git push --remote=<fork-remote> --bookmark='upstream-queue/<name>/<slug>'
```

- `upstream@<fork-remote>` is the published public anchor. `docs/flake-update.fork.md:14` calls it
  "the stable anchor". **verified**: it resolves to `ktxtouorppsz`, the same commit as
  `main@<upstream-remote>` (`jj log -r 'upstream@<fork-remote>'` and `jj bookmark list
  --all-remotes`). So a queue parented there rests on published public history only.
- `jj duplicate` copies and leaves the original chain intact. `docs/jujutsu-vcs.md:324` lists
  `jj duplicate <id> --onto <dest>` as the cherry-pick golden path. **verified.**
- `jj bookmark create <new-name>` is not the banned operation. The ban covers `jj bookmark set`
  for `main` and `upstream` (`docs/flake-update.fork.md:25`). **verified** by a read.
- `git.push` already defaults to the fork remote, so `--remote` is a second safeguard, not a
  requirement. **verified** with `jj config list`.

**(b) a fork-only change**

```bash
jj split -m 'feat(fork): ...' -- <files>
jj bookmark create 'fork-work/<name>/<slug>' -r @-
jj git push --remote=<fork-remote> --bookmark='fork-work/<name>/<slug>'
```

The maintainer folds `fork-work/*` into the fork `main`. The collaborator never runs
`jj sync-remotes`. See § F.

**(c) a flake update**

A collaborator runs the **fork half only**:

```bash
nix run '.#update'
devenv update
jj split -m 'chore(flake): update' -- flake.lock devenv.lock .flake.patches/
jj new fork-tip                      # park an empty single-parent @
jj bookmark create 'fork-work/<name>/flake-update' -r 'fork-tip'
jj git push --remote=<fork-remote> --bookmark='fork-work/<name>/flake-update'
```

They must **not** create the public-inputs commit (`docs/flake-update.fork.md:159`), and must
never queue the full lock. Reason, **verified**: the full lock on the fork chain holds 12 `ssh://`
URL lines, and the public lock holds 2 (§ E). The public-inputs split needs a public push at the
end, which only the maintainer can do.

**(d) upstream-safe on top of fork work** — § C4.

### C3. outside contributor

```bash
jj git clone --colocate https://github.com/nazarewk-iac/nix-configs.git nix-configs
cd nix-configs
# work in @, then:
jj split -m 'feat(...): description' -- <files>
jj bookmark create '<slug>' -r @-
jj git remote add mine https://github.com/<you>/nix-configs.git
jj git push --remote=mine --bookmark='<slug>'
gh pr create --repo nazarewk-iac/nix-configs --head '<you>:<slug>'
```

- The clone URL needs no key. `https://github.com/nazarewk-iac/nix-configs` is public.
- `jj git clone --colocate` — **unverified**, I did not run it. jj 0.44.0 is the version in this
  shell (`jj --version`, **verified**).
- "Push a feature branch, never over the primary" is the documented safe default
  (`docs/jujutsu-vcs.md:440-444`). **verified.**
- An outside contributor has **no** fork slot, so `kdn.jj.fork.enable` stays false and
  `fork/default.nix:50` emits no alias and no hook. **verified** by a source read. They cannot
  leak fork content, because they never held it. Their path is the simplest of the three.
- Change type (b), a fork-only change, does not apply. They hold neither the content nor the
  access.
- Change type (c), a flake update, works as `docs/flake-update.md` describes, with one open risk
  from § G. Change type (d) does not apply — they have no fork parents.

### C4. Worked example: an upstream-safe change on top of fork work

**Measured tree state.** **verified** with `jj log -r '<alias>'` for each alias:

```
@              zrytponuzysr  (empty working copy)
vtprpzrkvknv   chore(flake): update                        ← fork-side by construction: the full lock
vzrtokzpmqvn   docs(generalization): record the Lix flake laziness research      ← upstream-safe
mzprwzwusxpn   docs(generalization): rewrite the plan in Simple Technical English ← upstream-safe
rtsyynwvmoxr   docs(generalization): plan to make the modules reusable …          ← upstream-safe
sommnqortuuz   chore(devenv): keep the local slot settings as a tracked example   ← fork-leaked
zrtvyyymtrns   refactor(hosts/<private-host>): use kdn's shared ssh-access graph  ← fork-leaked
xxxuyknszklq   chore(upstream): merge                      ← tree-merge
```

| Alias | Count | Members |
|---|---|---|
| `to-rebase` | **6** | all six commits above the merge |
| `upstream-safe` | 4 | the three documentation commits **and** `chore(flake): update` |
| `fork-leaked` | 2 | the two fork-only commits |
| `merge-frozen` | 0 | the merge is mutable |

All three documentation commits are mutable. **verified** with
`jj log -r '<ids>' -T 'if(immutable,"IMMUTABLE","mutable")'`.

**`upstream-safe` over-reports.** It includes `chore(flake): update`, and that commit touches
`flake.lock` and `devenv.lock`. **verified** with `jj diff -r vtprpzrkvknv --name-only`. See § E
for why that matters.

**Collaborator route.** Duplicate the three documentation commits onto the public anchor. Do not
rebase them.

```bash
jj git fetch --remote=<fork-remote> --remote=<upstream-remote>
jj log -r 'upstream-safe'                     # 4 commits — drop the flake update by hand
jj duplicate rtsyynwvmoxr mzprwzwusxpn vzrtokzpmqvn --onto 'upstream@<fork-remote>'
# read the new head change id from jj's "Duplicated <old> as <new>" output
jj bookmark create 'upstream-queue/<name>/generalization-plan' -r <new-head>
jj git push --remote=<fork-remote> --bookmark='upstream-queue/<name>/generalization-plan'
```

`jj duplicate` accepts several revisions and rebuilds their shape on the destination. Quoted from
`jj duplicate --help` on jj 0.44.0, **verified**:

> When any of the `--onto`, `--insert-after`, or `--insert-before` arguments are provided, the
> roots of the specified commits will be duplicated onto the destination indicated by the
> arguments. Other specified commits will be duplicated onto these newly duplicated commits.

So three contiguous commits become a three-commit chain on the anchor. The exact output graph is
**unverified** — I did not run the command.

**Why not `jj rebase`.** `jj rebase -s rtsyynwvmoxr -d 'upstream@<fork-remote>'` also moves every
descendant, so it drags `chore(flake): update` off the fork chain and breaks the fork merge.
`-s` means the revision **and its descendants** (`docs/jujutsu-vcs.md:84`). **verified** by a
read; the resulting breakage is a reasoned consequence, so **unverified** in practice.

**Maintainer route for the same tree.** Extract the three commits in place, so the fork merge
gains them as ancestors on the upstream side:

```bash
jj log -r 'merge-frozen'                     # empty → the merge is mutable
jj rebase -r rtsyynwvmoxr -r mzprwzwusxpn -r vzrtokzpmqvn \
  --insert-after 'upstream-tip' --insert-before 'fork-tip'
```

**unverified.** Two open points: whether `jj rebase` accepts a repeated `-r` together with both
insert flags, and whether the current `upstream-tip` / `fork-tip` values (§ A4) make the insert
land where the maintainer wants. Check § A4 before you run it. `docs/jujutsu-vcs.md:320` verifies
only the single-revision form `jj rebase -r <A> --insert-after <B>`.

---

## D. The absent-maintainer case — queue mechanisms, ranked

Requirements: (i) the change is not lost, (ii) it leaks no private content, (iii) it needs no
rework when the maintainer returns. Rank by how little the collaborator must learn.

### 1. A dedicated queue bookmark on the private fork — **RECOMMENDED**

Commands: § C2 (a). The collaborator learns one bookmark name pattern and one push command.

- **Not lost.** The bookmark lives on the fork server, next to every other fork ref.
- **No leak.** The fork is private, so the push crosses no privacy boundary. Every public push
  stays with the maintainer, which is what the current tooling already assumes (§ A1).
- **No rework.** The queue is already parented on `upstream@<fork-remote>`, the published public
  anchor. The maintainer fetches, reviews, and fast-forwards.
- **Failure modes.**
  - The queue bookmark is invisible to every fork alias. `upstream-chain`, `upstream-tip`,
    `to-rebase`, and `upstream-safe` all measure the local stack above `tree-merge`, and a queue
    parented on the anchor sits outside that window. **verified** by a source read of
    `fork/default.nix:78-99`. So the maintainer must look for `upstream-queue/*` by hand. Fix it
    with a new alias in the slot (task work item).
  - `jj bookmark set` refuses a backward move without `--allow-backwards`
    (`docs/jujutsu-vcs.md:349`, **verified**). A collaborator who re-queues a rewritten change
    hits that refusal.
  - A pushed queue bookmark stays **mutable**, so a rewrite is possible but forces a force-push.
    **verified**: `immutable_heads() = trunk() | tags() | untracked_remote_bookmarks()`
    (`jj config list --include-defaults`), and jj tracks a bookmark it pushed. A tracked remote
    bookmark is therefore not immutable.
  - `jj sync-remotes` still exists in the collaborator's shell once the fork slot is on. Nothing
    stops them from running it (§ F).

### 2. A pull request from the collaborator's own public fork

- **Not lost.** Yes, GitHub holds it.
- **Leak: the worst of the four.** The collaborator pushes to a **public** remote, and defect 1
  (§ A5) disables the denied-content check on exactly that remote. A leak on a public GitHub fork
  is irreversible: git history plus the fork network.
- **No rework.** A PR merges cleanly, but only when the collaborator first lifts the change off
  its fork parents — the same work as mechanism 1, done in the open, where a mistake is permanent.
- **Learn:** a GitHub fork, an extra remote, a branch, a PR. Most of the four.
- **Verdict.** Acceptable only after checkpoint 001 fixes defect 1, and only for a change that
  touches no lock file and no host directory.

### 3. Patch files committed under a directory in the fork

- **Not lost.** Yes.
- **No leak** outward. But no check inspects a `.patch` blob beyond the denied-pattern list, so a
  patch text can carry a private string that the name-based check never sees (defect 2, § A5).
- **Rework: high.** The maintainer must apply the patch by hand. `git apply` is a raw git write,
  which this repo's rules forbid (`.agents/rules/jujutsu-vcs.md`, **verified**). The change loses
  its change id, its author metadata, and its commit boundaries.
- **Failure mode.** Patch rot. A patch that applies with fuzz produces silently wrong content.
- **Verdict.** A fallback only, for a collaborator who cannot push at all.

### 4. A direct `jj git push` to a personal public fork

- Same public exposure as mechanism 2, with no pull request and no review step.
- **Failure mode.** The collaborator may push `main`. Defect 1 leaves that push unchecked, and the
  leak is irreversible.
- **Verdict.** Never.

### Recommendation

**Mechanism 1 — a queue bookmark on the private fork.** Four reasons:

1. `git.push` already defaults to the fork remote, so the safe target needs no flag. **verified.**
2. The collaborator learns one new bookmark name pattern. Nothing else.
3. A mistake stays inside the private perimeter, so it is repairable.
4. The maintainer keeps sole control of every public push, which is exactly what every current
   procedure already assumes (§ A3).

Name the bookmark `upstream-queue/<collaborator>/<slug>` to avoid a collision. Put the task file
that records the change **inside** the queued commit, so the intent travels with the content.

---

## E. How a collaborator proves a change is upstream-safe

`jj fork-audit` is necessary and **not sufficient**. Measured proof:

| Measurement | Result | Command |
|---|---|---|
| `jj fork-audit -q 'upstream-safe'` | exit **0**, "no fork-sensitive content found" | **verified** |
| `ssh://` lines in the local `flake.lock` | **12** | `jj file show -r @ flake.lock \| grep -c 'ssh://'` — **verified** |
| `ssh://` lines in the public `flake.lock` | **2** | `git show refs/remotes/kdn/main:flake.lock \| grep -c 'ssh://'` — **verified** |
| lock nodes present locally and absent publicly | **5** | `comm -23` over `jq -r '.nodes\|keys[]'` — **verified** |
| does `upstream-safe` include a commit that touches `flake.lock`? | **yes** | `jj diff -r vtprpzrkvknv --name-only` — **verified** |

So the audit calls the `upstream-safe` set clean, while that set holds a `flake.lock` with ten
more private `ssh://` URL lines than the public lock. The reason is not defect 2 alone: the
`fork-direct` revset **does** check content through `diff_lines(glob-i:*<pattern>*)`
(`fork/default.nix:74`, **verified**), and `fork-audit.sh:148` greps file content at the revision
(**verified**). Both are pattern-based, and the denied-pattern list does not cover the private
URL text in the lock. A pattern check can only prove the absence of a **known** string.

So add checks that need no pattern.

```bash
PUB=refs/remotes/<upstream-remote>/main
BASE='upstream@<fork-remote>'
HEAD='<queue-head>'

# 0. sanity — the ref must resolve, or every check below reads as clean:
git ls-tree -r --name-only "$PUB" -- flake.nix | head -1     # must print flake.nix

# 1. pattern level — necessary, not sufficient:
jj fork-audit "$HEAD"

# 2. structural — reject a lock file and the local slot settings outright:
jj diff --no-pager --from "$BASE" --to "$HEAD" --name-only \
  | grep -E '^(flake\.lock|devenv\.lock|devenv\.slots\.local\.)' \
  && echo 'REJECT: the queue touches a lock file or the local slot settings'

# 3. path provenance — every touched path exists publicly, or a person reviews it:
while read -r f; do
  [ -n "$(git ls-tree -r --name-only "$PUB" -- "$f")" ] || echo "NEW PATH — review by hand: $f"
done < <(jj diff --no-pager --from "$BASE" --to "$HEAD" --name-only)

# 4. content level — no URL that the public remote does not already hold.
#    Run this on any revision that touches a lock file, and on the fork merge:
comm -23 <(jj file show -r "$HEAD" flake.lock | jq -r '..|.url? // empty' | sort -u) \
         <(git show "$PUB":flake.lock         | jq -r '..|.url? // empty' | sort -u)

# 5. read every added line by eye. Nothing replaces this step:
jj diff --no-pager --from "$BASE" --to "$HEAD" --git | grep '^+'
```

- Check 0 is mandatory. `git ls-tree` fails **silently** on a bad ref name, and then every path
  reads as fork-only and a real leak stays hidden (`docs/generalization-plan.md:259-261`,
  **verified**).
- `jj diff --from <X> --to <Y>` is the documented range form (`docs/jujutsu-vcs.md:313`,
  **verified**). `jj diff -r` takes one revision only, so it cannot span a queue.
- Check 4 prints nothing on a clean queue. On the current fork chain it prints the ten private
  URLs, so run it in a private terminal and never paste its output.
- Checks 2 and 3 are structural, so they hold with no pattern list. That is why they belong in the
  procedure and not in the hook.

**Structural rule, in words.** A queued upstream-safe change must not touch `flake.lock`,
`devenv.lock`, a private host directory, or the local slot settings. Each of those four is private
by construction, not by pattern.

---

## F. What each non-maintainer role must never run

### Fork collaborator

| Never run | Reason |
|---|---|
| `jj sync-remotes` | It calls `jj sync-upstream` first (`fork/default.nix:159`), which moves the local `upstream` bookmark (line 192) and then pushes to the **public** remote with raw git (line 193). With no public access the push fails after the bookmark move, and the repair needs `jj undo` or a banned backward `jj bookmark set`. **verified** by source. |
| `jj sync-upstream` | The inner half of the same command. Same failure. |
| `jj bookmark set main` · `jj bookmark set upstream` | Both bookmarks belong to the sync procedure. A hand-move breaks the topology the aliases read (`docs/flake-update.fork.md:25`). |
| `jj bookmark set … --allow-backwards` | It hides a divergence instead of a repair. |
| any push to the public remote — `jj git push --remote=<upstream-remote> …`, `git push <upstream-remote> …` | The pre-push guard skips every denied check for a non-fork remote (`pre-push.sh:64-67`). The push has no content protection at all. |
| `jj git push --bookmark=main` | It publishes the local fork chain over a shared bookmark. |
| `jj git push --all` | It can push `upstream` and other shared bookmarks in one step. |
| `git worktree` (and an Agent `isolation: "worktree"`) | A git worktree shares the single `.jj` store, and the race truncated three files to 0 bytes (`docs/jujutsu-vcs.md:220-240`). **verified** by a read. |
| `nix run '.#update'` on the public half | Step 3 of `docs/flake-update.fork.md` ends in a public push the collaborator cannot make. |

**`jj sync-remotes` confirmed by source, not by assumption.** Lines 150-174 define it; line 159
runs `jj sync-upstream`; lines 192-194 move the local `upstream` bookmark and then push to the
public remote and to the fork. It needs push access to both remotes. **verified.**

One more point that matters: `jj sync-remotes` **is** available to a collaborator, because
`fork/default.nix:50` gates it on `cfg.enable && cfg.fork.enable` and nothing else. **verified.**
So it is a live footgun, not a theoretical one. The task file proposes a `kdn.jj.fork.role` option
to remove it.

### Outside contributor

| Never run | Reason |
|---|---|
| `jj sync-remotes` · `jj sync-upstream` | They do not exist without the fork slot, and they target remotes the contributor does not own. **verified** by `fork/default.nix:50`. |
| `jj git push --remote=<upstream-remote> --bookmark=main` | Never push over the upstream primary. Open a pull request (`docs/jujutsu-vcs.md:440`). |
| `jj bookmark set main` · `jj bookmark set upstream` | Same reason. |
| `git worktree` | Same data-loss hazard as above. |

---

## G. Does the public repo stand alone for an outside contributor?

**Answer: partly. Record it as unverified.**

What I confirmed by reading the public ref:

- The public `flake.nix` declares exactly **one** `ssh://` input:
  `inputs.brew-tap--browsers-software--homebrew-tap.url =
  "git+ssh://git@github.com/browsers-software/homebrew-tap"` at line 14. **verified** with
  `git show refs/remotes/kdn/main:flake.nix | grep -n 'ssh://'`.
- The public `flake.lock` holds two `ssh` URL lines for that one input, and no other.
  **verified** with `git show refs/remotes/kdn/main:flake.lock | grep -n 'ssh'`.
- The target repo is public and reachable over https with no key.
  `docs/tasks/generalization-001-slots-sharing-readiness.md:130-132` records
  `"private": false`, `"visibility": "public"`, and a successful
  `git ls-remote https://github.com/browsers-software/homebrew-tap HEAD`. **verified** by a read
  of that record, not by a fresh run.
- The public `devenv.yaml` pins `nixpkgs: follows: nix-configs/nixpkgs`, and public
  `flake.nix:4` sets `inputs.nixpkgs.url = "github:nazarewk-iac/nixpkgs/nixos-unstable"` — a
  public fork, reachable with no key. **verified** with
  `git show refs/remotes/kdn/main:devenv.yaml`.
- No other input on the public ref uses a private transport. **verified** by the grep above.

What I could **not** confirm by reading alone:

- **unverified** — whether `nix flake check` succeeds on a fresh public clone with no SSH key.
  The `flake.lock` pins the tap by narHash, so Lix may serve it from the store or a cache and
  never fetch it. Any output that reads the tap forces a fetch over `ssh://`, and `ssh://` needs a
  GitHub key even for a public repo.
- **unverified** — whether an outside contributor can evaluate the Darwin host `hosts/anji` on
  Linux. `docs/generalization-plan.md:201-202` and `.agents/rules/repo-structure.md` both forbid a
  Darwin **build** on Linux; neither says anything about evaluation.
- **unverified** — whether `nix run '.#update'` can refresh the public `flake.lock` with no key,
  for the same `ssh://` reason.

The tests that would settle all three exist in the plan: Pattern V2, the adopter-hostile eval with
`SSH_AUTH_SOCK=` and an unusable key (`docs/generalization-plan.md:172-182`), and Pattern V3, the
scratch flake under `/tmp` (`:184-187`). **verified** by a read.
`generalization-001-slots-sharing-readiness.md:124-136` already proposes the one-line fix: change
that input to `github:Browsers-software/homebrew-tap`. That fix would remove the last known
transport blocker on the public ref.

---

## H. Day-one bootstrap for a new collaborator

### 1. Remotes

```bash
# fork collaborator — clone the private fork, then add the public remote:
jj git clone --colocate <private-fork-url> nix-configs      # flag unverified
cd nix-configs
jj git remote add <upstream-remote> https://github.com/nazarewk-iac/nix-configs.git
jj git fetch --all-remotes

# outside contributor — the public remote only:
jj git clone --colocate https://github.com/nazarewk-iac/nix-configs.git nix-configs
```

The public remote is not added for you. `kdn.jj.upstream.url` defaults to `null`
(`modules/slots/jj/default.nix:36`), and `enterShell` adds the remote only when that option is set
(`:101-103`). **verified** by a source read. Without the public remote, `upstream-incoming` and
`upstream-incoming-tip` fail, because both name `main@<upstream-remote>`
(`fork/default.nix:89-90`). **verified.**

### 2. Restore the local slot settings file

```bash
ls devenv.slots.local.*.example.nix
cp devenv.slots.local.<name>.example.nix devenv.slots.local.nix
```

- `.agents/rules/repo-structure.md` § "Local devenv slot settings" holds this step. **verified**
  by a read.
- One example file exists in the working copy, with the shape
  `devenv.slots.local.<name>.example.nix`. **verified** with `ls -la`. Its concrete name embeds the
  fork's own name, so this document does not print it.
- `.gitignore:42` ignores `/devenv.slots.local.nix`, so no commit chain can add or remove it.
  **verified** by a read.
- `devenv.nix:22` reads the file only when it exists:
  `localSlots = lib.optional (builtins.pathExists ./devenv.slots.local.nix) …`. **verified.**

### 3. Turn the fork slot on

The example file holds `kdn.jj.fork.enable = true`, the fork remote name, the fork URL, and the
fork's denied-pattern list. This document does not read that file, and does not print its
contents.

### 4. Re-enter the shell

```bash
exit
devenv shell        # or `direnv reload`
```

`modules/slots/jj/default.nix:85-90` symlinks the generated jj repo config on `enterShell`, and
every alias lives in that generated file. A shell already open keeps the old symlink. **verified**
by a source read.

### 5. Confirm

```bash
jj config get git.push                                       # → the fork remote name
jj log -r 'fork-tip'  --no-graph -T 'change_id.short()'
jj log -r 'upstream@<fork-remote>' --no-graph -T 'change_id.short()'
jj fork-audit --help
```

### What breaks silently when they skip step 2

- `devenv.nix:22` uses `builtins.pathExists`, so an absent file raises no error. `kdn.jj.fork.enable`
  stays false, and `fork/default.nix:50` then emits **nothing**: no revset alias, no
  `sync-remotes`, no `fork-audit` on `PATH`, no pre-push hook, and no `git.push` default.
  **verified** by a source read.
- The loud part: every fork revset fails with an unknown-alias error.
- **The silent part: the pre-push hook disappears.** Nothing checks a push at all. `devenv.nix:14-18`
  states the same failure mode in its own comment: "every setting in it turns off with no warning
  … The failure is silent." **verified** by a read.
- A second silent failure, one level worse: the file exists but leaves `deniedFilePatterns = []`.
  Then the hook installs and passes everything.
  `generalization-001-slots-sharing-readiness.md:48-52` records the mechanism — `grep` gets no
  `-e` argument and exits 2, and the `if` at `pre-push.sh:69` reads exit 2 as "no match", so the
  check passes. Recorded as given.
- Net effect for a new collaborator: the denied-pattern list comes from an untracked file, so the
  push protection is off by default on a fresh clone, and nothing says so.

---

## Every unverified claim, in one list

1. ~~Whether `jj git push` fires `.git/hooks/pre-push`.~~ **Settled 2026-09-09: it does not.**
   Measured in a throwaway colocated repo on jj 0.44.0. See § A5, defect 3.
2. ~~Whether the pre-commit hook `jj-check-fork-contamination` ever runs in a jj-only workflow.~~
   **Settled 2026-09-09: it does not.** `jj commit` fires no `.git/hooks/pre-commit`. See § A5.
3. The exact graph that `jj split -A upstream-tip -B fork-tip` produces on the current tree. The
   tip values are verified; the outcome is reasoned. § A4.
4. The exact graph that `jj duplicate <a> <b> <c> --onto <anchor>` produces. The `--help` text is
   quoted and verified; I ran no duplicate. § C4.
5. Whether `jj rebase` accepts a repeated `-r` together with `--insert-after` and
   `--insert-before`. § C4.
6. That `jj rebase -s <doc1> -d <anchor>` would drag the flake update off the fork chain. The
   `-s` semantics are verified from the docs; the breakage is reasoned. § C4.
7. ~~The `jj git clone --colocate` flag.~~ **Settled 2026-09-09: the flag exists on jj 0.44.0.**
   `jj git clone --help` lists `--colocate`. § C3, § H.
8. Whether `nix flake check` succeeds on a fresh public clone with no SSH key. § G.
9. Whether an outside contributor can evaluate `hosts/anji` on Linux. § G.
10. Whether `nix run '.#update'` refreshes the public lock with no SSH key. § G.
11. The consequence of a local `upstream` bookmark that sits ahead of `upstream@<fork-remote>`
    after a denied public push. The state is verified from the source order; the downstream effect
    is reasoned. § A2.
