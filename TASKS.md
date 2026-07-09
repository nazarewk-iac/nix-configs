# Tasks

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

### Improve the fork validation logic

1. verify every commit in the list of changes independently in pre-push
2. make the pre-commit (and therefore the `prek run`) verify that commits on top of upstream, but without a fork do not contain fork-specific changes

### Fix modules/slots/ usage & implementation for devenv

I can see that modules/slots don't actually set `config.devenv` options and instantiate that, but instead import directly which is plain wrong.

1. move over all `config =` into `config.devenv =` within modules/slots
2. register it properly as flake's devenvModules.default

call out any issues you encounter.

### Update the modules architecture for slots/ considerations

Some module architecture only makes sense for modules/universal, but not module/slots/, let's call those out

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

### Convert docs/ (and other markdowns) to OKF

see https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf

convert existing entries to this format and make using it an universal rule shared to downstream configs
