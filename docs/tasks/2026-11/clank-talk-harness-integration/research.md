---
type: Research
description: Source-verified findings on ClankTalk 0.1.3, its OpenCode V2 plugin, its Pi extension, its sandbox and its policy semantics, and what each finding means for this repository.
task: definition.md
authored_by: agent
timestamp: 2026-11-17T08:18:24+01:00
---

# ClankTalk integration research

## Sources

- <https://clank.talk/> — overview and feature list.
- <https://clank.talk/docs.html> — install, `AGENTS.talk`, harness notes, limitations.
- <https://clank.talk/reference.html> — language and policy reference.
- <https://github.com/bigskysoftware/clank-talk> at `master`, commit `97f71f9`, 2026-11-13.
  Files read: `package.json`, `src/js/host.js`, `src/js/sandbox.js`,
  `src/js/harnesses/opencode/{index,tui,state,channel}.js`, `src/js/harnesses/pi.js`,
  `src/js/harnesses/pi-host.js`, and `src/md/infrastructure/{opencode,pi}.md`.

The upstream docs call the OpenCode integration "not tried in a real opencode V2" and the Pi
integration a "first version built". Both statements are current at the commit above.

## Package facts

- npm `clank-talk@0.1.3`, BSD-3-Clause, `"type": "module"`, `engines.node >= 22`.
- No runtime dependencies. `typebox` is an optional peer dependency, and Pi supplies its own copy.
- Binaries: `clank-talk` and `clank-talk-mcp`.
- `files`: `bin/` and `src/js/`. The native integration code is inside the published tarball:
  - OpenCode plugin: `src/js/harnesses/opencode/` (`index.js`, `tui.js`, `state.js`,
    `channel.js`). The folder has no `package.json`.
  - Pi extension: `src/js/harnesses/pi.js` and `pi-host.js`.
  - MCP server: `bin/clank-talk-mcp.js`.
- The package has no build step. A Nix package can unpack the tarball and wrap the two binaries.
  `buildNpmPackage` is unnecessary.

## Native OpenCode plugin

- Load path: `"plugins": ["<path>/src/js/harnesses/opencode"]` in `opencode.jsonc`. A folder with
  no `package.json` loads its `index` file, and the TUI part is loaded beside it.
- The default export is `{ id: "clank-talk", setup }`.
- `setup(ctx)` adds `clank_talk` with `options.codemode = false`. Code Mode therefore cannot call
  the tool around the guard.
- The guard has two walls:
  - `ctx.session.hook("context")` deletes every tool that is not `clank_talk`, `question`, or a
    name in `allow harness tools`.
  - `ctx.permission.hook("evaluate")` denies the matching permission actions. It always turns
    `clank_talk_ask` into a prompt, so a broad allow rule cannot answer for the human.
- `ask` uses a plugin RPC channel to the TUI part. If no TUI says `seen` within 2 seconds, it
  falls back to OpenCode's permission prompt for a yes/no question. Other questions return null.
- `/clank-talk on|off` and `/taint` live in the TUI part. The server part reads the per-session
  state file `.talk/harness/opencode-<session>.json`.
- An allowed harness tool call is recorded in the ClankTalk audit by `tool.execute.after`.
- The source was checked against `anomalyco/opencode` branch `dev`, `@opencode/plugin` 2.2.7.
  This repository runs OpenCode 2.2.5.

### Important detail: `setup` adds the tool before the mode check

`setup` calls `ctx.tool.transform` unconditionally. The mode check (`sessionMode`) happens in the
`context` hook and the permission hook, not before the tool is added. The `clank_talk` tool's
`execute` does not check the mode either. A loaded plugin therefore gives a normal session a
script tool that bypasses the OpenCode `edit`/`bash` permission prompts. The integration must not
load the plugin in a normal session. A gate in `setup` (environment variable or shim) is
mandatory.

## Native Pi extension

- Entry: `src/js/harnesses/pi.js`; `package.json` also declares `pi.extensions`.
- `session_start` registers `clank_talk`, reads the `--clank-policy` and `--clank-policy-hash`
  flags, computes the mode, and calls `applyTools()`.
- `applyTools()` while on: `pi.setActiveTools([TOOL_NAME, ...allowed])`. While off:
  `pi.setActiveTools(startTools + clank_talk)`.
- A `tool_call` guard blocks every other tool, including MCP tools and Code Mode calls.
- `ask` uses `ctx.ui.select` or `ctx.ui.input`. With no UI, the answer is null.
- `/taint` runs `clank-talk taint --tui` as a child process with the terminal. The model cannot
  run it.
- The footer shows `clank-talk: on, untainted` and the taint count.
- `executionMode: "sequential"`, because calls share one session. Progress updates at most every
  500 ms.
- Upstream limits: the extension runs in Pi's process with full user rights; another extension
  can register tools or bypass the guard. For a strict run, use
  `pi --no-extensions -e <path>/src/js/harnesses/pi.js`. `--no-extensions` disables discovery and
  the built-in extensions, but explicit `-e` paths still load. The repository wrapper passes every
  extension with `-e`, so a strict launcher must call the real Pi binary or the wrapper needs a
  branch that omits its extension list.

### Important detail: the extension adds `clank_talk` when off

`applyTools()` adds `clank_talk` to `startTools` when the mode is off. A loaded extension therefore
changes a normal session. The integration must not load the extension in a normal session. A
dedicated `clank-pi` wrapper is the simplest gate.

## Root and enablement

- `projectRoot(given, cwd, env)` = `given || env.CLANK_TALK_ROOT || cwd`.
- The OpenCode plugin calls `projectRoot(null, ctx.location.directory)`; the Pi extension calls
  `projectRoot(null, ctx.cwd)`. Both honour `CLANK_TALK_ROOT`.
- `AGENTS.talk` is read from the root. `harnessMode` decides the mode in this order:
  1. `require clank-talk` in `AGENTS.talk` wins.
  2. `/clank-talk on|off` for the session.
  3. On when an `AGENTS.talk` exists.
- Consequence: a tracked root `AGENTS.talk` turns ClankTalk on for every session that loads the
  integration. It has no effect on a session that does not load it. This is why the gate belongs
  in the launcher, not in the policy.
- If the root has no `AGENTS.talk` but a parent does, the host warns and tells the agent to ask
  the human. The root never changes on its own.

## Sandbox

- macOS: `sandbox-exec`. Linux: `bwrap`. Other platforms: no sandbox, and a sandboxed `run` is an
  error.
- System reads: `/usr`, `/bin`, `/sbin`, `/System`, `/Library`, `/etc`, `/private/etc`, `/opt`,
  `/dev`, `/lib`, `/lib64`, and the timezone directories.
- Cache reads from the real home: `.npm`, `.cache`, `.m2/repository`, `.gradle/caches`,
  `.gradle/wrapper`, `.cargo/registry`, `.rustup/toolchains`, `go/pkg`, `Library/Caches`.
- Secret paths are blocked even inside an allowed folder: `.ssh`, `.aws`, `.gnupg`,
  `.config/gh`, `.netrc`, `.docker`, `.kube`, `.npmrc`, `.m2/settings.xml`,
  `.gradle/gradle.properties`, `.cargo/credentials`, `.pypirc`.
- The program's install folders are added read-only. For `nix`, that is the `nix` package, not the
  whole `/nix/store`.
- `/nix/store` is not a system read. The Nix daemon socket is not a system read. A sandboxed
  `nix build` therefore fails unless the policy adds those paths.
- `run` without `in a sandbox` is not sandboxed. The documentation calls this "where the sandbox
  ends".

## Policy semantics that matter here

- `AGENTS.talk` is protected: scripts cannot change `.talk` files, `@/talk/`, `@/.talk/`, or
  hidden files and folders, unless an `allow changes to` line names them. `.env`, `.env.*` and
  `.envrc` are always banned.
- `tool` defines a name the agent can call. `run` is allowed only inside a tool. The agent cannot
  run a program directly.
- `run` never uses a shell. Each `with` value is one argument.
- `allow env` lists the environment variables that `run` passes. A program that PATH finds inside
  the project is refused; use its path.
- `before` hooks can reject a step, ask the human, or read the session taint. A hook cannot change
  the step and cannot run a program.
- `git` is hardened: no hooks, no pager, no external diff, fast-forward-only merge, no force push.
  A repository config that can run programs stops git.
- `taint` defaults to on. It taints on `fetch`, an `untrusted tool`, or a subagent answer. The
  default asks before `push` and a `fetch` with a secret. `taint required` cannot be turned off.

## This repository's integration points

- OpenCode: `modules/slots/opencode/default.nix` writes `opencode.jsonc` and generates
  `.opencode/plugins/*.ts`. The slot has a free-form `settings` option, so a `plugins` key can be
  added without a new option. `.opencode/plugins/` is auto-loaded, but the `plugins` array is the
  documented way to load a folder.
- Pi: `devenv.nix` builds `piWrapped` from `pi.lib.mkCodingAgent` with an `extensions` list.
  `packages/pi-coding-agent-extensions/default.nix` holds the vendored extensions. A new extension
  path can be added to the list; the wrapper passes `--extension` for each entry.
- The repository's own commands: `jj` (0.47.1), `devenv`, `nix`, `prettier`, `kdn-journal`,
  `kdn-jj-meta`, `kdn-okf`, `okf-agent-memory`, `ai-xf`, `okf-guard`, `okf-rs`, `okflint`,
  `okph`.
- `kdn-jj-meta` autodiscovers the harness session from the environment: `OPENCODE_SESSION_ID` /
  `OPENCODE_MODEL` for OpenCode, `PI_SESSION_ID` / `PI_MODEL` for Pi, and `AI_AGENT` as the
  harness fallback. A ClankTalk `run` passes only the variables in `allow env`, so the policy must
  name them or the trailers lose the session id.
- The agent instruction files: `AGENTS.md`, `data/pi/AGENTS.md`, `.agents/rules/*`. A ClankTalk
  session needs one short section that says "use `clank_talk`, not shell or edit".
- The checks: a class 2 change (shell and harness) needs C1, C3, C4, C6 and C7. C7 is
  `opencode plugin list`, `opencode models` and `pi --list-models`.

## Measured environment

- OpenCode `v2.2.5`; the real binary is `opencode-2.2.5`; the `opencode` on PATH is the kdn
  wrapper.
- Pi `1.5.1`.
- Node `24.22.2` is on PATH; `nixpkgs#nodejs` is `24.22.2`. The package needs Node 22 or later.
- ClankTalk is not installed in the current shell.

## Open findings for the design

- The OpenCode plugin's `projectRoot` is fixed at `setup`. A shim can set `KDN_CLANK_TALK=1` and
  call the upstream `setup` only when set. The TUI part must be re-exported behind the same gate,
  or a normal session gets `/clank-talk` and `/taint` commands that do nothing useful.
- The Pi extension has no environment gate. A `clank-pi` wrapper that calls the real Pi binary with
  `--no-extensions -e <pi.js>` is the simplest opt-in, and it also removes the "another extension
  bypasses the guard" limit. The repository wrapper cannot be reused as is: it passes every
  extension with `-e`, and explicit `-e` paths survive `--no-extensions`.
- The `AGENTS.talk` policy is the main work. A minimal first policy can be small: jj
  status/diff/log/new/commit/split/absorb/describe, `nix eval`, one bundle check, `prettier`,
  `kdn-journal` and `rg`.
- `clank-pi` with `--no-extensions` also removes `model-discovery`, which registers the live
  `litellm-dynamic` provider. The default Pi model in this repository uses that provider. Add
  `-e <model-discovery>` back, or pin a static model, and check `pi --list-models` under the
  launcher.
- The policy hash for Pi is optional for a trial. A wrong hash makes every call an error, so a
  stale hash is a hard lockout; verify the value from the built file.
- The OpenCode shim's absolute import of a store path must be tested. If OpenCode's plugin loader
  rejects it, copy the four plugin files into the generated shim folder and patch the one gate
  line instead.
