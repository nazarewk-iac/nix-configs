# Jujutsu (jj) VCS — Fork Workflow

> **Agent note:** This file is installed as `.claude/rules/jujutsu-vcs.fork.md` in repos with
> `kdn.jj.fork.enable = true`. See [jujutsu-vcs.md](jujutsu-vcs.md) for the fork-agnostic base
> patterns this extends, and [flake-update.fork.md](flake-update.fork.md) for the concrete
> update workflow that uses this topology.

When a private fork remote exists alongside the public upstream remote, `main` is a merge of
both lines and `@` sits on top of both `main` and `upstream`:

```
main@<upstream-remote> ──► ...upstream-chain... ──► upstream
                       \                                    \
                        \────────────────── main ──────────► @
                       /
main@<fork-remote> ──► ...fork-chain...
```

`upstream` and `main` are **bookmark** names in this repo's convention — `upstream` tracks the
public chain tip, `main` tracks the merge of both chains. Both are distinct from the **remote**
names (`kdn.jj.upstream.remote` / `kdn.jj.fork.remote`), which may differ.

---

## Keeping @ current

After fetching both remotes:

```bash
jj git fetch --remote=<upstream-remote> --remote=<fork-remote>
jj rebase -s @ -d main -d upstream
# equivalently:
jj rebase -s @ -d main -d main@<upstream-remote>
```

---

## Required finish state (fork repo)

`@` must be empty with **both** `main` and `upstream` as parents:

```bash
jj bookmark set upstream -r 'latest(upstream-candidates)'
jj bookmark set main -r 'latest(fork-candidates)'
jj rebase --revision <main-merge-id> --destination upstream --destination main@<fork-remote>
jj new -d main -d upstream
```

`upstream-candidates` and `fork-candidates` are revset aliases defined by the `kdn.jj.fork`
devenv slot (`~description("") & ~fork` / `~description("") & fork`) — they pick out the latest
named, non-fork-tagged commit and the latest named, fork-tagged commit respectively.

> **Warning:** `jj describe` on a multi-parent `@` (e.g. when `@` sits on top of both `main` and
> `upstream`) creates a merge commit inheriting all parents — including fork ones. Always commit
> upstream-side work while `@` has a single upstream-chain parent, then restore the multi-parent
> `@` with `jj new -d main -d upstream` afterwards.

**Before declaring done:**
```bash
# 1. check for stray commits (orphans from rebases):
jj log -r '::(@ | main | upstream)' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# 2. verify no fork-side commits leaked into the upstream chain
# (grep for the fork-remote name; the only allowed match is the base main@<upstream-remote>/upstream@<fork-remote> anchor):
jj log -r 'main@<upstream-remote>..upstream' --no-graph -T 'change_id.short() ++ " parents=" ++ parents.map(|p| p.change_id().short() ++ "(" ++ p.bookmarks() ++ ")").join(",") ++ " " ++ description.first_line() ++ "\n"' | grep "<fork-remote>" | grep -v "main@<upstream-remote>"

# 3. verify upstream has exactly one parent:
jj log -r 'parents(upstream)' --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'

# 4. verify the build:
devenv build shell
```

If `upstream` has more than one parent, rebase it onto just the upstream-chain tip:

```bash
jj rebase --revision upstream --destination <upstream-chain-tip-id>
jj bookmark set upstream -r upstream
```

Ask the user whether to squash, relocate, or abandon any strays found. Fix build errors before
finishing.

---

## Rebasing the fork merge after new upstream commits

When new commits land on the upstream side (e.g. post-update fixes), rebase the fork merge
commit to include them, then restore `@` on top of both:

```bash
jj rebase --revision <merge-change-id> \
          --destination upstream \
          --destination main@<fork-remote>
jj bookmark set main -r <merge-change-id>
jj rebase -s @ -d main -d upstream
```

See [flake-update.fork.md](flake-update.fork.md) for the concrete workflow this feeds into.

---

## Constructing a new fork merge commit

Creating (or recreating) the `main` merge topology is a legitimate, structural use of `jj new` —
not a work checkpoint:

```bash
jj new <fork-tip> <upstream-tip> -m 'chore(merge): merge in upstream'
jj bookmark set main -r @
jj new -d main -d upstream
```
