---
type: Rule
description: Requires any fork that carries local patches, and any vendored copy of one, to follow the fork-and-vendor convention.
timestamp: 2026-11-03T13:50:00+01:00
---

# Forking and vendoring

Full docs: [docs/guides/git-forking.md](../../docs/guides/git-forking.md) (the fork, the bookmark
layout, upstream updates) and [docs/pi-extension-forks.md](../../docs/pi-extension-forks.md)
(Pi-specific patch and vendor steps).

When a vendored component must change and upstream does not have the change:

- Reference every repository path through `g-dir <host>/<owner>/<repo>`, and clone or refresh it with
  `g-get <host>/<owner>/<repo>`; never hard-code `/tmp/...` or `~/dev/...`. Both are shell helpers from
  `packages/git-utils`. For a jj-managed clone use `GIT_UTILS_KDN_UPDATE=0 g-get ...` (clone only) and
  then `jj git fetch`, because `g-get` updates with `git pull --rebase`, which fights a colocated jj
  working copy.
- Fork into `nazarewk-iac` and cut the patch **from the vendored revision**, not from `main`.
- Drive the fork with jj: one **bookmark per feature** cut from the vendored rev, then join them
  with `jj new <feature-a> <feature-b>` and `jj bookmark set main -r @`. The fork's `main` IS the
  joined integration line (upstream lives at `upstream/main`), and `rev` pins `main`'s commit.
- One small, upstreamable patch commit. Prefer a config switch over a hard-coded behaviour.
- Run the fork's `tsc --noEmit` and tests before you push.
- Vendor by pinned `rev` and `hash` with a `+nazarewk.N` suffix; bump all three together.

Pi extensions add three steps (full list in the Pi doc):

- Build locally (`--option builders ""`) when the remote builder rejects an unsigned output, then
  confirm Pi loads with no `Failed to load extension`.
- Sync the copies: `checks/pi-harness/extensions/` and `~/.pi/agent/agents/` (a copy, not a link).
- A colon in an unquoted frontmatter value is invalid YAML and breaks the load. Quote it.

## A fork pin is a normal dependency

Pushing a commit to a fork and bumping the pin in the consumer is **ordinary operations**, not an
exception: it is the same act as committing to a non-forked repository and bumping the input. Treat
it that way — a fork used as a flake input is a dependency like any other, and its `main` is a
branch like any other.

Rules that follow from that:

- **Pin by commit SHA, never by branch.** A pin is immutable; a branch is not. The hash is part of
  the pin: `nix flake prefetch <url>` or `nix-prefetch-url --unpack` on the exact revision.
- **Rebasing or force-pushing your own fork does not break existing pins.** The old objects stay
  reachable from the pinned commit, so every consumer keeps building. The only cost is that
  `nix flake update <input>` cannot fast-forward across the rewrite — bump `rev` by hand.
- **A local patch file beside a package is a temporary state.** It is allowed only while the fork
  cannot be pushed. As soon as the commit is on the fork, switch the input to the fork revision and
  delete the patch: two copies of the same change drift, and the patch rots silently against
  upstream.
- **A pushed fork commit is reviewable like any other commit.** The consumer's diff names the rev;
  the fork's history explains it. No separate ceremony is needed.
