---
type: Backlog
description: Backlog list of planned improvements and tasks for the repository.
timestamp: 2026-07-10T12:19:48+02:00
---

# Tasks

> ⚠️ **Legacy file — being phased out.** New tasks live as one file per task under
> `docs/tasks/<task>.md`. Before starting work on any entry below, **first move it** to
> `docs/tasks/<task>.md`, then work it there. When a task is done, tag it `status: done` in its
> frontmatter and add a sibling `docs/tasks/<task>.done.md` with the solution. When the last
> entry here is migrated out, **delete this file.**

## Backlog

### Improve mcp-gateway tool prompts

**Context:** After watching live JSON-RPC traffic through mcpsnoop, the current gateway prompts
are bare — essentially "Invoke Tool → json blob" with no natural-language context about what
each tool does or when to use it.

**Goal:** Rewrite the gateway's tool descriptions and/or system prompt so the LLM gets
meaningful guidance: what each backend is for, when to prefer it over another, and how to
interpret results.

**Reference:** https://assistant.kagi.com/share/f456cad0-8678-4199-bf33-87d9a9d60d52
— session capturing observations on prompt quality and ideas for improvement.

**Starting point:** `.devenv/mcp-gateway.yaml` backend `description` fields and any
gateway-level system prompt configuration in `modules/slots/mcp/default.nix`.

**Status:** partially addressed — `kdn.mcp.pretty-print` (`modules/slots/mcp/pretty-print/`)
replaces Claude Code's native "Tool use" approval dialog for `gateway_invoke` calls with a
native Tk window. This was not the first design tried:

- A PreToolUse hook attaching a `systemMessage` preview was built first, but empirically
  `systemMessage` renders only *after* the dialog resolves (as a `⎿ PreToolUse:... says: ...`
  annotation), never inside the dialog itself before the user answers.
- `mcp-gateway`'s `surfaced_tools` (pinning specific backend tools directly in `tools/list`,
  bypassing the `gateway_invoke` dispatcher) was tried next — confirmed correct in the gateway's
  Rust source, but empirically unreliable: stdio warm-start is fired async and races the very
  first `tools/list`, so a surfaced tool's schema is usually still absent when Claude Code's
  client-side tool list gets fixed for the session. Abandoned; see
  [docs/mcp-tools-report.md](docs/mcp-tools-report.md) for detail.
- Final design: a **PermissionRequest** hook (not PreToolUse) that builds a readable preview via
  a per-backend Nix-assembled Python plugin package
  (`kdn.mcp.pretty-print.formatters.<name>`, contract: `select(ctx) -> bool` /
  `get_permissions_info(ctx) -> str | (fields, body)`), shows it in a generic native Tk dialog
  (title + key/value metadata rows + plain-text body + Allow/Deny), and returns that decision
  directly — Claude Code never renders its own dialog for a call this hook handles. Confirmed
  working live. basic-memory contributes a plugin splitting `write_note`/`delete_note` into
  metadata fields (title, directory, project) with just the raw content in the body.

This covers the *approval-time* half of the original goal (what a specific call is about to do);
the LLM-facing tool-description/system-prompt half (what each backend is *for*, when to prefer
one over another) is still open.

Also produced: [docs/mcp-tools-report.md](docs/mcp-tools-report.md) — full tool inventory across
all enabled backends, safety categorization, and an analysis of why Claude Code's
`permissions.allow`/`ask`/`deny` can't do per-backend-tool allow-listing through the gateway's
single-dispatcher-tool design (recommends mcp-gateway's own `security.firewall.rules` as the
next lever, not yet wired up). [docs/mcpsnoop.md](docs/mcpsnoop.md) gained a "Testing a new
backend/tool surface" workflow section documenting the sweep-and-capture procedure used to
produce that report, for reuse next time backends/tools change.

### Improve the fork validation logic

1. verify every commit in the list of changes independently in pre-push
2. make the pre-commit (and therefore the `prek run`) verify that commits on top of upstream, but without a fork do not contain fork-specific changes

### `prek run` fails with "You have unmerged paths" during jj conflict resolution — ignore for now

**Status:** deprioritized — do not let this block other work, but keep it in mind so it
doesn't quietly reappear and get misattributed to a real `prek`/hook bug.

**Symptom:** the `git-hooks-run` PostToolUse hook (`cd "$DEVENV_ROOT" && prek run`) fails with:
```
error: You have unmerged paths. Resolve them before running prek
```
even though `jj status` shows a clean/expected working copy state (no `(conflict)` marker on
`@` or its named ancestors).

**Root cause:** this is a jj/git colocation artifact, not a `prek` bug. When a jj commit that
was involved in a conflict gets its content resolved (e.g. by editing the file directly, or via
`jj squash`/`jj new -d a -d b` merge topology), jj updates its own commit tree correctly, but
the colocated `.git/index` can be left holding stale 3-way merge stages for the affected path
(confirmed via `git ls-files -u -- <path>` showing stage 1/2/3 entries, and `git status` showing
`both modified: <path>` under "Unmerged paths") — even after `jj status` reports no conflicts
and `jj git export` reports "Nothing changed." `prek`/`pre-commit` refuses to run while git's
index has unmerged paths, regardless of jj's own state.

**Reproduction:** create a two-parent jj merge commit where both parents independently touch
the same region of a file (e.g. two divergent chains both add an identical section to a doc),
then resolve the resulting conflict by writing the correct content directly to the working
copy. `jj status` goes clean, but `git status` continues to show the path as unmerged until
`git add <path>` is run manually to clear the stale index stage.

**Workaround (git-only, matches the "fall back to git for what jj can't do" exception):**
```bash
git add <path>   # clears the stale 3-way merge stage; does not affect jj's own state
```

**Goal (when picked back up):** decide whether the `git-hooks-run` hook (or a new dedicated
check) should detect and auto-clear this specific stale-index-only case (verified via `jj
status` showing no conflict but `git status` showing unmerged paths) before invoking `prek`, so
agents don't have to diagnose it by hand each time. Low priority — rare, and has a known
one-line fix once recognized; don't let it block the jujutsu-vcs overhaul or other work.

### Implement the multi-arch Linux builder + container image stitching

**Goal:** make this `aarch64-darwin` host build **both** `aarch64-linux` and `x86_64-linux`
derivations locally (no cloud CI, single authoritative host `/nix/store`, disposable builders),
then stitch per-arch OCI images into one multi-arch image index entirely inside Nix (no
daemon/registry round-trip).

**Handover docs** (present viable options with tradeoffs; pick one when implementing):
- [docs/multi-arch-builder.md](docs/multi-arch-builder.md) — dual-arch builder setup (Rosetta
  Linux for x86_64, single host store).
- [docs/multi-arch-container-builder.md](docs/multi-arch-container-builder.md) — assembling the
  OCI image index locally with `nix2container`, depends on the builder above.

**Status:** design/handover docs written; implementation not started.

### jj VCS convention to always end up on top of a merge commit

Maybe should make a VCS convention and a script that would leave the history in a forked repository
 as follows:

```
                       /- fork-tip / (pushed) merge - fork
@ - (unpushed) merge <
                       \- upstream-tip - upstream

```

in cases when the @ doesn't yet depend on a merge change OR the merge change was already pushed.

This is in contrast to convention to have `@` depending only on `fork-tip` and `upstream-tip`,
having `@` be descendant of a unpushed merge makes it trivial to issue `jj split -A upstream-tip -B fork-tip`.

The script should detect the current situation and amend it with
`jj new fork-tip upstream-tip -m 'chore(upstream): merge'`
or throw an error if it's in an "unknown" situation.

The script might be doable as a `jj` command and/or mix of aliases? Should do a research on whether it's possible.

### jj workspaces script wrapper

Should probably create a jj workspaces wrapper script that would create, list, get and remove
workspaces as a minimal arguments, single-command operations.

Might warrant adding a new workspace-name entry to `kdn-slug`.

### Fix `$DEVENV_ROOT` reaching into the main repo from a sibling `jj workspace add`

**Context:** [docs/vcs-workspaces.md](docs/vcs-workspaces.md) documents the hazard in full. An
agent working in a `jj workspace add` sibling dir inherits a `$DEVENV_ROOT` baked in at
shell-entry time that still points at the **main** checkout — it does not follow `cd` into the
sibling. The `git-hooks-run` PostToolUse hook (`modules/slots/nix/default.nix`,
`cd "$DEVENV_ROOT" && prek run`) then runs `prek run` against the **main** repo's git state on
every Bash call from the sibling, racing the main checkout on the shared colocated `.git`
(observed as `.git/index.lock` contention on 2026-07-30).

**Goal / preferred direction:** sub-agents in a sibling workspace should run their own `devenv
shell` built from the correct (workspace) root, so all `DEVENV_*` vars re-point. Decide whether
to additionally make the `git-hooks-run` hook robust to a stale `$DEVENV_ROOT` — e.g. derive the
hook's target from the actual jj/git root of `$PWD` rather than the inherited `$DEVENV_ROOT`, or
guard it to no-op when `$PWD` is not inside `$DEVENV_ROOT`.

**Related:** the untracked-but-build-required-file half of the same doc (e.g.
`packages/jj-mcp/package-lock.json`, since fixed by tracking it) — audit for any other gitignored
build inputs that a sibling workspace wouldn't receive.

**Unverified idea to explore — run full sub-agent sessions inside dedicated zellij panes.**
Instead of spawning sub-agents via the harness Agent tool (whose `Bash` calls don't persist
shell state and inherit a stale `$DEVENV_ROOT`, and whose every call fires the `git-hooks-run`
PostToolUse hook against the main repo), launch each sub-agent as a full `claude` session inside
its own zellij pane that has already `devenv shell`-entered from the correct workspace root. The
coordinator drives them via the `zellij-llm` tooling (`packages/llm/zellij-llm/`, spawn /
spawn-and-watch / peek / list). Hypothesised benefits: the sub-agent's *own* commands then run
with correct `DEVENV_*` and the git-hooks hook is scoped to that pane's env, not the main repo —
addressing both halves of this hazard at once. Open questions (all unverified): how the
coordinator feeds tasks to and reads results back from an interactive `claude` in a pane; session
lifecycle/teardown; permission-prompt handling inside a pane; whether this is worth the
orchestration overhead vs. just fixing the hook. Prototype and measure before committing to it.

A further lever this shape unlocks (that the harness Agent tool does not): because the
sub-agent is a real process in a pane the coordinator controls, the coordinator could **pause,
kill, and respawn it in a fresh pane with a freshly-entered `devenv shell`** — recovering from a
hung build, a wedged tool, or a stale environment by fully reloading the devenv rather than
being stuck with whatever env the sub-agent started with. Open questions here too: preserving /
handing off the sub-agent's task context across a respawn, detecting "stuck" vs. "slow", and
avoiding orphaned zellij sessions/panes on kill.

### Convert docs/ (and other markdowns) to OKF

see https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf

convert existing entries to this format and make using it an universal rule shared to downstream configs

### analyze Jujutsu docs/ references

Some or all docs/ references in Jujutsu documents might assume being directly in nix-configs. Link them to all repos and/or instruct how to fetch them using Nix.
