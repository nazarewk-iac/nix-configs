---
type: Solution
description: A pinned ClankTalk package, opt-in OpenCode and Pi launchers, a repository AGENTS.talk policy, and the NixOS sandbox and OpenCode folder-plugin fixes that make a guarded session work.
task: definition.md
authored_by: agent
timestamp: 2026-11-17T09:50:00+01:00
---

# ClankTalk harness integration — solution

## Root cause analysis

The repository had no controlled runtime for an agent. Both harnesses exposed a shell, edits, jj,
Nix, MCP and subagents, and the permission model was a prompt per tool. ClankTalk offers a single
script tool with a human-owned policy, but a plain MCP registration would not have worked:

- The native integrations are in-process. The OpenCode plugin hides the other tools in a `context`
  hook and denies their permission actions; the Pi extension calls `setActiveTools`. An MCP server
  cannot hide the harness tools, and Pi has no MCP elicitation, so `ask` would always be null.
- Both native integrations add `clank_talk` even when the mode is off. Loading them in every
  session would give a normal session a script tool that bypasses the harness permission prompts.
- The upstream sandbox is not NixOS-ready. It reads only a program's install folder, so a Nix
  binary cannot find its interpreter and libraries; it also fails on the Nix store symlinks at a
  devenv project root.
- OpenCode 2.2.5 does not load a folder plugin whose `index.js`/`tui.js` are Nix store symlinks, and
  `opencode plugin list` shows `-` for a folder plugin even when it loads.
- This repository uses jj, not git, and Nix needs the store, the daemon and the network. Neither
  fits a default sandbox.

## Solution

### Package

`packages/clank-talk/default.nix` pins `clank-talk@0.1.3` from the npm tarball, wraps the
`clank-talk` and `clank-talk-mcp` entry points with Node, and exposes the OpenCode plugin folder and
the Pi extension. Two NixOS patches are applied in `postPatch`:

- add `/nix/store` to the sandbox's read-only system paths, so a Nix binary can start;
- skip hidden Nix store symlinks at the project root, because `bwrap` cannot mount over a symlink
  destination.

### OpenCode

`modules/den/aspects/opencode.nix` (the module this shell actually uses) and
`modules/slots/opencode/default.nix` (the slot for other consumers) generate a gated shim at
`.opencode/plugins/kdn-clank-talk/`:

- `index.js` calls the upstream `setup` only when `KDN_CLANK_TALK=1`;
- `tui.js` gates the upstream TUI part the same way;
- `package.json` exports both parts.

OpenCode discovers the folder automatically. The files are installed as **regular files** by
`enterShell`, not as store symlinks. `clank-opencode` sets `KDN_CLANK_TALK=1` and
`CLANK_TALK_ROOT`, then starts `opencode --standalone`, so the variable reaches the server that
loads the plugin.

### Pi

`devenv.nix` builds a second `mkCodingAgent` wrapper, `clankPiWrapped`, with only the ClankTalk
extension and `model-discovery`, and `--no-extensions`. `model-discovery` registers providers, not
tools, so the live model catalog stays. `clank-pi` runs that wrapper with `CLANK_TALK_ROOT` at the
repository root. The normal `pi` wrapper is unchanged.

### Policy

`AGENTS.talk` defines the daily loop: jj status/diff/log/new/commit/split/absorb/describe/bookmark,
`nix_eval`/`nix_build`/`check_bundle`/`nix_fmt`, `prettier`, `kdn-journal`, `kdn-jj-meta` and a
read-only `rg`. Hooks refuse the knowledge bundle, `secrets/`, `*.sops.yaml` and `git push`, and ask
the human before jj writes, Nix builds, `nix fmt`, the devenv check and `kdn-jj-meta`. Nix runs
without a sandbox because it needs the store, the daemon and the network; the human gate is the
control.

The policy is tracked: `.gitignore` unignores `AGENTS.talk`. The review hardening also refuses a
change to the agent instruction files (`AGENTS.md`, `CLAUDE.md`, `data/pi/AGENTS.md`,
`.agents/rules/`), a jj fileset in a `files` list, a move or delete of the knowledge bundle, and
`prettier` on the knowledge bundle or secrets. A global `before run` hook keeps every program either
in a sandbox or on the named jj/Nix allowlist.

### Docs and instructions

- `docs/clank-talk.md` — the launchers, the policy, taint, audit, requirements and limits.
- `AGENTS.md` and `data/pi/AGENTS.md` — the short rule: in a ClankTalk session, use `clank_talk`,
  not a shell or the other file tools.
- `docs/pi-harness.md` and `docs/mcp-setup.md` — links to the new guide.

## Verification steps

Package and policy:

```sh
nix build --no-link --print-out-paths .#clank-talk
# /nix/store/q2v6bk0r2nzlx0bcz98j0dbkixf4881i-clank-talk-0.1.3

/nix/store/q2v6bk0r2nzlx0bcz98j0dbkixf4881i-clank-talk-0.1.3/bin/clank-talk harness --json --root .
# {"agentsTalk":true,"required":false,"allowed":[],"untrusted":[],"errors":[]}
```

Policy smoke tests, run through the runtime with a fake `ask` that answers yes:

```text
jj_status                      -> done, working-copy status printed
nix_eval '.#clank-talk.version'-> done, 0.1.3
write @/.agents/knowledge/...  -> failed: the knowledge bundle is written by okf-agent-memory
git push                       -> failed: this repository never pushes from an agent session
jj_commit files: [.agents/...] -> failed: the commit names a protected path
jj_commit files: ['all()']     -> failed: use explicit project paths, not a jj fileset
write @/AGENTS.md              -> failed: the agent instruction files are human-owned
prettier @/.agents/knowledge/  -> failed: the knowledge bundle is not formatted
check_bundle bundle: 'nope'    -> failed: unknown bundle (before the human is asked)
nix_build '.#clank-talk'       -> done, asked the human, built the package
write + undo                   -> the file is removed
rg 'clank_talk'                -> done, inside the sandbox
prettier <file>                -> done, inside the sandbox
```

Shell and harness:

```sh
devenv shell -- true
# ✓ devenv:enterShell

devenv test
# • opencode: the ClankTalk shim is a regular file

nix build --no-eval-cache -L .#checks.x86_64-linux.den-eval-opencode
# den eval opencode: 15 of 15 assertions pass
```

Guarded OpenCode session (private server):

```sh
clank-opencode run --format json --model requesty/qwen3.8-flash \
  "The only tool you have is clank_talk. Call clank_talk now with the script: print 2 + 2."
# tool_use clank_talk {"script":"# Simple arithmetic test\nprint 2 + 2"} -> "4"
```

Guarded Pi session:

```sh
clank-pi --model requesty/qwen3.8-flash -p \
  "The only tool you have is clank_talk. Call clank_talk with the script: print 2 + 2."
# Output: 4
```

Normal sessions stay unchanged:

```sh
opencode run --format json --model requesty/qwen3.8-flash \
  "Use the execute tool with code: return 2 + 2."
# tool_use execute -> "4"
pi --list-models
# the full fleet, as before
```

The audit recorded both guarded sessions:

```text
-- session opencode-50fa --
== 09:39:57  script 1  Simple arithmetic test  (done, 1 step) ==
  print 2 + 2
--
-- session pi-47d5 --
== 09:40:14  script 1  print the result of 2 + 2  (done, 1 step) ==
  print 2 + 2
--
```

## Follow-up notes

- **Interactive TUI commands.** `/clank-talk on|off` and `/taint` live in the TUI part. The
  headless `opencode run` and `clank-pi -p` smoke tests reach the server part but not the TUI. Run
  them once in an interactive session.
- **`opencode plugin list`** shows `-` for the folder plugin even when it loads. Do not use that
  column as the check for this plugin; a `clank-opencode` session is the check.
- **Broad bundles are red for an unrelated reason.** `bundle-core`, `bundle-den` and `bundle-pkgs`
  failed on the parallel rosec work (`attribute 'rosec' missing` in `den-eval-coverage`) and on a
  remote-builder signature error for `kdn-jj-meta`. The narrow `den-eval-opencode` check passes.
- **`clank-pi` drops the orchestrator and the status rail.** This is deliberate: `delegate` spawns
  children that do not inherit the guard, and `pi-atelier` is not needed in a script-only session.
  A later trial can add `pi-atelier` back if the status surface matters.
- **MCP.** `clank-talk-mcp` is packaged but not in the gateway. Pi has no MCP elicitation, so the
  native extension is the preferred route.
- **Upstream churn.** 0.1.3 is under construction. A bump can change the plugin API, the extension
  entry or the policy syntax; re-run the smoke tests after a bump.
