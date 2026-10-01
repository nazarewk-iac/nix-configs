---
type: How-To
description: Fork a git repository with the GitHub CLI, rename the remotes, and disable unused repository features.
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

| Flag | Result |
|---|---|
| `--remote-name nazarewk` | Accepted, but no effect when you use a repository argument. The clone path hardcodes fork=`origin` and upstream=`upstream`. |
| `--remote` | Error: `the --remote flag is unsupported when a repository argument is provided`. |

### Rename the remotes

`gh repo fork` sets the fork as `origin` and renames the old origin to `upstream`. Rename the remotes
so the fork is `nazarewk` and upstream is `origin`:

```bash
repo="$(g-dir github.com/nazarewk/nix-rosetta-builder)"
git -C "$repo" remote rename origin nazarewk
git -C "$repo" remote rename upstream origin
git -C "$repo" remote -v
```

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

| Feature | Command |
|---|---|
| Issues | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_issues=false` |
| Wiki | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_wiki=false` |
| Projects | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_projects=false` |
| Pull requests | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F has_pull_requests=false` |
| Merge commits | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_merge_commit=false` |
| Squash merges | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_squash_merge=false` |
| Rebase merges | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_rebase_merge=false` |
| Auto-merge | `gh api -X PATCH repos/nazarewk/nix-rosetta-builder -F allow_auto_merge=false` |
| Actions | `gh api -X PUT repos/nazarewk/nix-rosetta-builder/actions/permissions -F enabled=false` |
| Discussions | `gh repo edit nazarewk/nix-rosetta-builder --enable-discussions=false` |

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
