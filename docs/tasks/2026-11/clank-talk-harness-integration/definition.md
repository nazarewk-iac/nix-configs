---
type: Task
description: Integrate ClankTalk's sandboxed scripting runtime into the OpenCode and Pi harnesses behind an opt-in launcher, with a repository AGENTS.talk policy for jj, Nix and the agent journal.
status: done
solution: done.md
authored_by: agent
timestamp: 2026-11-17T08:18:24+01:00
---

# Integrate ClankTalk with the OpenCode and Pi harnesses

> ✅ **Done** — see the solution in [done.md](done.md).

Upstream: <https://clank.talk/> · <https://github.com/bigskysoftware/clank-talk>

## Context

ClankTalk is a scripting language and runtime for agents. It replaces the shell with a small,
readable language. Scripts stay inside the project root. Programs run only through tools that a
human defines in `AGENTS.talk`, optionally in an OS sandbox. The runtime also adds secrets, taint
tracking, an audit log and undo.

ClankTalk is an MCP server. It also has native integrations:

- an OpenCode V2 server plugin at `src/js/harnesses/opencode/`;
- a Pi extension at `src/js/harnesses/pi.js`.

This repository runs two harnesses: OpenCode 2.2.5 and Pi 1.5.1. Both expose a broad tool surface:
a shell, file edits, jj, Nix, MCP servers and subagents. A ClankTalk session replaces that surface
with one `clank_talk` tool and a policy that this repository owns.

Upstream is version 0.1.3 and "under construction". The OpenCode plugin has not run in a real
OpenCode V2. The Pi extension is a first version. Treat this task as a controlled trial, not a
default switch.

## Problem

A plain MCP registration is not enough. Five properties make this integration larger than one
config line.

1. **The native integrations are in-process.** The OpenCode plugin adds `clank_talk`, deletes the
   other tools in the `context` hook, and denies their permission actions. The Pi extension
   registers `clank_talk` and calls `setActiveTools` with `clank_talk` plus the allowed names. An
   MCP server alone gives a weaker result: it cannot hide the harness tools, and Pi has no MCP
   elicitation, so `ask` always returns null.

2. **The guard removes the harness features this repository relies on.** In OpenCode it hides
   `execute`, subagents, skills and MCP tools. In Pi it hides `delegate` from `pi-orchestrator`,
   `pi-atelier`, `pi-hashline-edit`, `session-digest`, `ask_user` and the skills. The integration
   must choose which of them stay, and must not allow a tool whose children run unguarded.

3. **This repository uses jj, not git.** ClankTalk ships a hardened git and no jj command. The
   policy must define jj tools, and they must keep the repository rules: explicit file sets, no
   push, one unnamed `@` at the tip.

4. **Nix does not fit the default sandbox.** The sandbox reads system folders and tool caches. It
   does not read `/nix/store`, and it does not open the Nix daemon socket. A `nix build` needs the
   store, the daemon and usually the network. The task must choose a narrow, explicit route for
   Nix, or keep Nix out of ClankTalk mode.

5. **A loaded plugin changes a normal session even when ClankTalk is off.** The OpenCode plugin
   adds the `clank_talk` tool in `setup` before it checks the mode, and the Pi extension adds it in
   `applyTools`. A session with no `AGENTS.talk` therefore gets a script tool that bypasses the
   harness permission prompts. The integration must not load either integration in a normal
   session.

## Goal

1. `pkgs.clank-talk` is pinned to one upstream version, with no runtime `npx` and no network at
   start. It exposes the `clank-talk` and `clank-talk-mcp` binaries, the OpenCode plugin directory
   and the Pi extension file.
2. `clank-opencode` and `clank-pi` start a guarded session in this repository. Plain `opencode`
   and plain `pi` keep their current tools and behaviour.
3. A tracked `AGENTS.talk` gives the agent the tools it needs here: file read and edit (built in),
   jj status/diff/log/new/commit/split/absorb/describe, Nix evaluation and bundle checks,
   formatting, the agent journal, and read-only search.
4. Hooks protect `AGENTS.talk`, `.talk/`, `talk/`, `.env*`, `secrets/`, `*.sops.yaml` and
   `.agents/knowledge/`. A `git push` is refused.
5. `/taint` and `/clank-talk on|off` work in both harnesses. Each action lands in `.talk/audit/`.
6. A smoke test proves an edit, a tool run, an `ask`, an `undo` and a taint review. A second test
   proves that a normal session is unchanged.
7. `docs/clank-talk.md` records the setup, the policy, the lost features and the off switch.

## Proposed approach

### 1. Package

Add `packages/clank-talk/default.nix`. Fetch the pinned npm tarball, unpack it, and wrap the two
binaries with Node 22 or later. The package has no runtime dependencies; `typebox` is an optional
Pi peer that Pi supplies. Expose `passthru.opencodePlugin` (`src/js/harnesses/opencode`) and
`passthru.piExtension` (`src/js/harnesses/pi.js`). Do not use `npx -y`: it resolves a floating
version at run time and needs the network.

### 2. Enablement

Use an opt-in launcher. Commit `AGENTS.talk` at the root, and make the launchers the only way the
integration loads.

- **OpenCode:** load a small shim folder instead of the upstream plugin. The shim `index.js` calls
  the upstream `setup(ctx)` only when `KDN_CLANK_TALK=1`; the shim `tui.js` re-exports the upstream
  TUI part behind the same gate. `clank-opencode` sets the variable. Add the shim folder to the
  `plugins` array of `opencode.jsonc`, so a normal session loads a shim that does nothing.
- **Pi:** `clank-pi` starts Pi with only the ClankTalk extension. `--no-extensions` disables
  discovery and the built-in extensions, but **explicit `-e` paths still load**. The repository
  wrapper passes every extension with `-e`, so `clank-pi` cannot simply add `--no-extensions` to
  the wrapper. It must call the real Pi binary with the repository system prompt and one
  `-e ${clank-talk}/src/js/harnesses/pi.js`, or the wrapper needs a strict branch that omits its
  extension list. `--no-extensions` also removes `model-discovery`, which registers the live
  `litellm-dynamic` provider that the default model uses. Keep `model-discovery` with a second
  `-e` when the session needs the live catalog: it registers providers, not tools, so it does not
  weaken the guard. The same choice applies to the status extensions (`pi-atelier`, `timestamps`,
  `idle-marker`): they do not add tools, but they do add UI code to the guarded process.

The alternative, loading the upstream integration in every session and using `/clank-talk off`,
is rejected: a normal session would still get the `clank_talk` tool and bypass the harness
permission prompts.

### 3. Policy

Write `AGENTS.talk` with a small daily-loop tool set.

- **Top lines:** `allow env PATH, HOME, AI_AGENT, OPENCODE_SESSION_ID, OPENCODE_MODEL,
PI_SESSION_ID, PI_MODEL` so `kdn-jj-meta` can attribute a change with the right harness and
  session. `allow changes to @/.github/` only if a tool needs it. Do not allow changes to
  `.agents/knowledge/`: `okf-agent-memory` owns that bundle. Name only the fetch hosts a tool
  needs, or none.
- **Tools:**
  - `jj_status`, `jj_diff`, `jj_log`, `jj_show`, `jj_new`, `jj_describe`, `jj_commit`,
    `jj_split`, `jj_absorb`, `jj_bookmark`. `jj_commit` and `jj_split` take an explicit file list
    and a message; `jj_absorb` takes an explicit file list. None of them pushes.
  - `nix_eval` (read-only), `nix_build`, `check_bundle` (a bundle name from a fixed list),
    `nix_fmt`, `prettier`.
  - `kdn_journal` (read-only), `kdn_jj_meta`, `rg` (read-only search), `devenv_shell_check`
    (`devenv shell -- true`).
- **Hooks:**
  - `before change`: reject `AGENTS.talk`, `.talk/`, `talk/`, `.env*`, `secrets/`,
    `*.sops.yaml` and `.agents/knowledge/`.
  - `before git`: reject `push`.
  - `before nix_build` and `before check_bundle`: `ask` the human, because these run without a
    sandbox.
  - `before run`: require `in a sandbox`, except the named `nix_*` and `jj_*` tools.
- **Taint:** keep the default `taint on`. Add `taint asks before push, secrets, commit, network
runs, new hosts` only if the trial shows the default is too narrow. Do not use `taint required`
  in the first trial: a mistake is then hard to clear.

### 4. Nix route

Choose one route and record the reason.

- **A. Unsandboxed, human-gated tools (recommended).** `nix_build` and `check_bundle` run `nix`
  without `in a sandbox`, and a `before` hook asks the human for each call. The agent still cannot
  run an arbitrary program; it can call only the named tools.
- **B. Sandboxed with explicit paths.** Add `reads of '/nix/store'`, `writes to '~/.cache/nix'`
  and the daemon socket. This gives every tool with that line the same privilege as the daemon. It
  is not a sandbox for Nix. Do not choose B.
- **C. No Nix in ClankTalk mode.** Use ClankTalk for reading, editing and jj; run builds in a
  normal shell. This is the smallest first step.

### 5. Verification

- `nix build --no-link --print-out-paths .#clank-talk` succeeds.
- `clank-pi` starts, `clank_talk` is the only tool, `/taint` opens, and a script edits a file,
  runs `jj_status`, asks a question, and undoes the edit.
- `clank-opencode` starts, `opencode plugin list` shows the shim with a real id, `clank_talk` is
  the only tool, and `/taint` opens.
- A normal `pi` session still shows `delegate`; a normal `opencode` session still shows its usual
  tools and no `clank_talk`.
- `.talk/audit/<date>.log` contains the edit, the tool call and the ask.
- A `git push` in a script is refused; a change to `.agents/knowledge/` is refused.
- `nix_eval` and one bundle check work through the policy.

## Scope

In scope:

- `packages/clank-talk/` and the package overlay;
- `devenv.nix` for the Pi launcher, and `modules/slots/opencode/` or a new slot for the OpenCode
  shim;
- `AGENTS.talk`, `AGENTS.md` and `data/pi/AGENTS.md` (a short conditional ClankTalk section);
- `docs/clank-talk.md`, with links from `docs/pi-harness.md` and `docs/mcp-setup.md`;
- `checks/` only if a harness load check is needed.

Out of scope:

- A ClankTalk fork. Use the pinned upstream and a local shim.
- Replacing the OpenCode permission baseline or the MCP gateway for other harnesses.
- Making ClankTalk the default for every session in this repository.
- A policy tool for every repository task; start with the daily loop.

## Acceptance

- [ ] `pkgs.clank-talk` builds from a pinned tarball; `clank-talk --version` prints the pinned
      version; no `npx` and no network at start.
- [ ] `clank-pi` and `clank-opencode` start a guarded session; plain `pi` and plain `opencode` do
      not load the integration.
- [ ] The policy exposes the jj, Nix and journal tools; the hooks refuse the protected paths and
      `git push`.
- [ ] `/taint` and `/clank-talk on|off` work in both harnesses.
- [ ] The audit log records the smoke-test actions.
- [ ] `docs/clank-talk.md` is complete, and the class 2 checks in
      [docs/post-change-checks.md](../../../post-change-checks.md) pass.
- [ ] A normal session is unchanged: `pi --list-models` and `opencode plugin list` match the
      before state.

## Risks

- Upstream 0.1.3 can change the plugin API, the extension entry, or the policy syntax. Pin the
  tarball and keep the shim small.
- The OpenCode plugin has not run in a real V2. Treat the first run as a debug session and record
  the failures in this task.
- The guard and the orchestrator disagree. If `delegate` stays allowed, its children are not
  guarded; if it is hidden, the repository loses its delegation model. Do not mix the two in one
  session.
- `--no-extensions` in `clank-pi` does not remove explicit `-e` paths. The repository wrapper
  passes every extension with `-e`, so a strict launcher must call the real Pi binary or the
  wrapper needs a strict branch. The same flag also removes `model-discovery`; add it back with a
  second `-e` if the session needs the live `litellm-dynamic` catalog, or pin a static model. Test
  `pi --list-models` under the launcher.
- Nix without the daemon socket is not usable; the daemon socket is a privilege boundary. Do not
  put it in a sandbox that also runs untrusted tools.
- `run` without `in a sandbox` is not sandboxed. A hook can enforce the line, but only for the
  tools that the policy defines.
- Two harnesses, one policy. `allow harness tools` matches OpenCode permission actions and Pi tool
  names differently; verify both.

## Open questions

1. Is ClankTalk a daily driver, a "sensitive task" mode, or a research trial? The answer sets the
   enablement model.
2. Which harness features stay in a ClankTalk session? `question`/`ask_user` yes; `delegate` no;
   skills? read-only MCP memory?
3. Does OpenCode load a folder plugin from the `plugins` array with `index.js` and `tui.js` as
   expected, and does the shim's absolute import of the store path work? Test both before the
   policy work.
4. Is a harness policy file with `--clank-policy-hash` worth the lockout risk, or is `AGENTS.talk`
   enough for the trial?
5. Should the MCP server join the gateway for Claude Code, or does this task stop at OpenCode and
   Pi?
6. Confirm that the policy lives at the root. The alternative is a generated file that the launcher
   binds for the session; that adds a race with a second session in the same checkout.

The trial resolved these: opt-in launchers, no `delegate`, Nix route A (unsandboxed and
human-gated), the policy at the root, and no MCP gateway entry. See [done.md](done.md).

## Related

- [ClankTalk docs for humans](https://clank.talk/docs.html) and
  [for agents](https://clank.talk/reference.html).
- [Upstream repository](https://github.com/bigskysoftware/clank-talk).
- [research.md](research.md) — the source-verified findings behind this task.
- [docs/pi-harness.md](../../../pi-harness.md) — the Pi harness and its extension inventory.
- [docs/mcp-setup.md](../../../mcp-setup.md) — the MCP gateway.
- [docs/post-change-checks.md](../../../post-change-checks.md) — class 2 checks for the shell and
  harnesses.
- [pi-harness-consolidation](../pi-harness-consolidation/definition.md) — the delegation model
  that a ClankTalk session must not silently break.
