---
type: How-To
description: Fork a git repository with the GitHub CLI, rename the remotes, keep the patch line on jj bookmarks joined into main, disable unused repository features, and vendor the result by pinned revision.
timestamp: 2026-10-01T17:38:07+02:00
---

# Fork a Git Repository

Use `gh repo fork` to copy a repository to your own account. This guide gives the general steps.
The worked example forks `cpick/nix-rosetta-builder` to `nazarewk/nix-rosetta-builder`.

## When to fork

Fork a repository when you need your own copy. Common reasons:

- You want to propose a change upstream with a pull request.
- You want a private or personal variant of a public project.
- You do not have write access to the source repository.

A fork is a full GitHub repository under your account. It keeps a link to the source repository.

## Fork and clone

Run one command to fork and clone in one step:

```bash
gh repo fork cpick/nix-rosetta-builder \
  --clone \
  --default-branch-only \
  -- "$(g-dir github.com/nazarewk/nix-rosetta-builder)"
```

- `--clone` clones the new fork.
- `--default-branch-only` forks only the default branch (`main`). Drop this flag to copy all branches.
- `-- "$(g-dir ...)"` passes a git clone target after `--`. The clone lands at
  `~/dev/github.com/nazarewk/nix-rosetta-builder`.

This repo clones repositories into `~/dev/github.com/<owner>/<repo>`. The `g-dir` helper prints that
path. For example, `g-dir github.com/nazarewk/nix-rosetta-builder` prints
`~/dev/github.com/nazarewk/nix-rosetta-builder`.

Do not pass these flags:

| Flag                     | Result                                                                                                                      |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `--remote-name nazarewk` | Accepted, but no effect when you use a repository argument. The clone path hardcodes fork=`origin` and upstream=`upstream`. |
| `--remote`               | Error: `the --remote flag is unsupported when a repository argument is provided`.                                           |

### Rename the remotes

`gh repo fork` sets the fork as `origin` and renames the old origin to `upstream`. Rename the remotes
so the fork is `nazarewk` and upstream is `origin`:

```bash
repo="$(g-dir github.com/nazarewk/nix-rosetta-builder)"
git -C "$repo" remote rename origin nazarewk
git -C "$repo" remote rename upstream origin
git -C "$repo" remote -v
```

## Keep the patch line on jj bookmarks, joined into `main`

A fork that carries local patches needs a branch layout, and this is the same for any repository we
vendor: one **bookmark per patch**, joined by a two-parent change that is the fork's `main`.

### Paths and clones: always `g-dir` and `g-get`

Never hard-code a scratch path. `g-dir <host>/<owner>/<repo>` prints where this machine keeps that
repository (`$HOME/dev/<host>/<owner>/<repo>` unless `GIT_UTILS_KDN_BASE_DIR` says otherwise), and
`g-get <host>/<owner>/<repo>` clones it there, or fetches and updates it when the directory already
exists. Both live in `packages/git-utils` and are on the shell PATH:

```bash
repo="$(g-dir github.com/nazarewk/<repo>)"
```

For a **jj-managed** fork, clone only and let jj do the fetching. `g-get` updates an existing clone
with `git pull --rebase`, which fights a colocated jj working copy:

```bash
GIT_UTILS_KDN_UPDATE=0 g-get github.com/nazarewk/<repo>   # clone if missing, never pull
jj git init --colocate --repository "$repo"               # first time only
jj -R "$repo" git remote add upstream https://github.com/<owner>/<repo>.git
jj -R "$repo" git fetch --remote upstream
```

### One bookmark per patch

Cut every patch from the revision you currently build, never from `main`:

```bash
jj new <vendored-rev> -m "feat: <patch>"
# ... edits, tests ...
jj bookmark create <patch>          # short name, no owner prefix
```

### Join the patches into `main`

A change with two parents is a merge; nothing is rewritten. Keep the working copy empty so the
build point is always `@-` and it is the `main` bookmark:

```bash
jj new <patch-a> <patch-b> -m "merge <patch-a> and <patch-b>"
jj bookmark set main -r @
jj new                               # @ empty; @- is the join, bookmarked main
```

Add a later patch with `jj new main <new-patch>` and `jj bookmark set main -r @`.

### Push and consume

```bash
jj git push --bookmark main --bookmark <patch>
```

The consumer pins `main`'s commit id. "The vendored line" and "the fork's main" are then the same
thing, so no branch name has to be remembered on a bump.

### Upstream moves

`upstream/main` is the pristine copy, not the fork's `main`:

```bash
repo="$(g-dir github.com/nazarewk/<repo>)"
jj -R "$repo" git fetch --remote upstream
jj -R "$repo" rebase -s <patch> -d upstream/main   # repeat per patch bookmark
jj new <patch-a> <patch-b> -m "merge ..."
jj bookmark set main -r @
jj new
```

Consequence, recorded because it reverses an older habit: the fork's `main` is **not** identical to
upstream. It is the joined integration line, and `upstream/main` holds the pristine copy. That is
the price of a single always-buildable bookmark; the alternative — vendoring a topic branch
directly — needs a branch name in every bump and loses the merge topology.

## Disable features

`gh repo fork` has no feature-disable flags. Fork and disable are two steps. After the fork, use
`gh repo edit` for a clean result:

```bash
gh repo edit nazarewk/nix-rosetta-builder \
  --enable-issues=false \
  --enable-wiki=false \
  --enable-projects=false \
  --enable-discussions=false \
  --enable-merge-commit=false \
  --enable-squash-merge=false \
  --enable-rebase-merge=false
```

Use `gh api` when `gh repo edit` has no flag for a feature. Use `-F` for a JSON boolean. Do not use
`-f`, because `-f` sends the string `"false"`.

| Feature       | Command                                                                                 |
| ------------- | --------------------------------------------------------------------------------------- |
| Issues        | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_issues=false`                |
| Wiki          | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_wiki=false`                  |
| Projects      | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_projects=false`              |
| Pull requests | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_pull_requests=false`         |
| Merge commits | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_merge_commit=false`        |
| Squash merges | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_squash_merge=false`        |
| Rebase merges | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_rebase_merge=false`        |
| Auto-merge    | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_auto_merge=false`          |
| Actions       | `gh api -X PUT repos/nazarewk/nix-rosetta-builder/actions/permissions -F enabled=false` |
| Discussions   | `gh repo edit nazarewk/nix-rosetta-builder --enable-discussions=false`                  |

The REST PATCH endpoint has no `has_discussions` field. Use GraphQL for Discussions, or use the
`gh repo edit` command above.

## Actions on forks

GitHub disables Actions on a fresh fork by default. The message is: "Workflows don't run in forked
repositories by default. You must enable GitHub Actions in the Actions tab." Scheduled workflows
are also disabled by default on a public fork.

`GET /repos/{owner}/{repo}/actions/permissions` reports `{"enabled":true}` even when Actions do not
run. Confirm the real state with `gh workflow list`. Force Actions off with the `actions/permissions`
PUT command in the table above.

## Caveats

- GitHub requires at least one merge method. If you disable all three, the API returns HTTP 422.
  When you never merge pull requests, disable pull requests (`has_pull_requests=false`) and keep one
  merge method enabled.
- Fork visibility is inherited. A public fork of a public repository cannot become private.
- `--default-branch-only` drops upstream branches and tags from the fork.
- `gh repo fork` has no `--disable-*` flags. The CLI rejects them.
- The Actions disable call needs admin on the fork. The upstream repository returns HTTP 403.

## Pinning the fork as a flake input

A fork that feeds a flake is a dependency, not an incident. Pushing to it and bumping the pin is the
same operation as a commit in a non-forked repository.

- Pin the **commit SHA** and its hash; a branch name is not a pin.
- A rebase or force-push to your own fork leaves old pins valid — the objects stay reachable — but
  `nix flake update` cannot fast-forward across it, so bump `rev` by hand.
- Prefer the fork revision over a local `.patch` file next to the package. The patch is a stopgap
  for "the fork cannot be pushed yet"; keeping both is how they drift.
