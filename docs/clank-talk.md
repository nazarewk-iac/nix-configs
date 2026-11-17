---
type: Guide
description: Run a guarded ClankTalk session in OpenCode or Pi — the launchers, the AGENTS.talk policy, the audit and taint review, and the limits of the sandbox.
authored_by: agent
timestamp: 2026-11-17T09:45:00+01:00
---

# ClankTalk sessions

[ClankTalk](https://clank.talk/) replaces the shell with a small, readable scripting language. A
ClankTalk session gives the agent one tool, `clank_talk`. File access stays inside the project.
Programs run only through the tools in [`AGENTS.talk`](../../AGENTS.talk), and a human confirms
the Nix builds. The runtime adds an audit log, undo, taint tracking and a sandbox for the tools
that ask for one.

The normal `opencode` and `pi` sessions do not load ClankTalk. Use the launchers:

```sh
devenv shell
clank-opencode        # OpenCode, guarded
clank-pi              # Pi, guarded
```

## What the launchers do

| Launcher         | What it sets                                                                                                                                    |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `clank-opencode` | `KDN_CLANK_TALK=1`, `CLANK_TALK_ROOT` at the repository root, and `opencode --standalone` (a private server so the variable reaches the plugin) |
| `clank-pi`       | Runs a second Pi wrapper built from the same configuration, with `--no-extensions` and only the ClankTalk extension plus `model-discovery`      |

The OpenCode plugin is a shim package at `.opencode/plugins/kdn-clank-talk/`. Its `index.js` calls
the upstream `setup` only when `KDN_CLANK_TALK=1`; its `tui.js` does the same. A normal session
loads the shim, and the shim does nothing. The shim is installed as **regular files** by
`enterShell`, not as Nix store symlinks: OpenCode 2.2.5 does not load a folder plugin whose files
are symlinks.

The Pi launcher uses a second `mkCodingAgent` wrapper, not the normal `pi` wrapper. It passes
`--no-extensions` and an explicit `-e` for ClankTalk. It also keeps `model-discovery`, which
registers the live `litellm-dynamic` provider; it registers providers, not tools, so it does not
weaken the guard. It drops `pi-orchestrator`, `pi-atelier`, `ask_user`, `session-digest`,
`pi-hashline-edit` and the `btw` skill.

## The policy

[`AGENTS.talk`](../../AGENTS.talk) is the human-owned policy. The agent cannot change it, and it
cannot change any `.talk` file.

- **Tools:** jj (`jj_status`, `jj_diff`, `jj_commit`, `jj_split`, `jj_absorb`, ...), Nix
  (`nix_eval`, `nix_build`, `check_bundle`, `nix_fmt`), `prettier`, `kdn-journal`, `kdn-jj-meta`
  and a read-only `rg`.
- **Hooks:** a change to `.agents/knowledge/`, `knowledge/`, `secrets/`, a `*.sops.yaml` or the
  agent instruction files (`AGENTS.md`, `CLAUDE.md`, `data/pi/AGENTS.md`, `.agents/rules/`) is
  refused. A jj fileset in a `files` list is refused. A `git push` is refused. A `jj` write, a Nix
  build, `nix fmt`, the devenv shell check and `kdn-jj-meta` ask the human first. A `before run`
  hook keeps every other program in a sandbox or on the named jj/Nix allowlist.
- **Nix route:** Nix runs **without** a sandbox, because it needs the store, the daemon and the
  network. The agent can call only the named `nix_*` tools, and each one asks the human. Do not add
  the Nix daemon socket to a sandbox: it is a privilege boundary.

Call a tool with two parameters by name:

```talk
jj_commit with files: [@/src/a.nix, @/src/b.nix], message: 'fix the parser'
check_bundle with system: 'x86_64-linux', bundle: 'bundle-core'
```

## Taint and the audit

A `fetch`, an untrusted tool or a subagent answer taints the session. While it is tainted, a push
and a fetch with a secret ask the human first. Review the inputs with:

- `/taint` in the OpenCode TUI or the Pi session;
- `clank-talk taint` in a terminal (list, `show`, `approve`, `--tui`);
- `taint review` in a script, only when the human asks for it.

The audit is `.talk/audit/<YYYY-MM-DD>.log`. It records every read, change, tool call, git command,
fetch and question, with the script that did it. The runtime keeps three days by default.

## Requirements

- **bubblewrap** must be on `PATH` for `in a sandbox` on Linux. The devshell installs it on
  Linux; macOS uses `sandbox-exec`.
- The `clank-talk` package patches two NixOS assumptions in the upstream sandbox:
  - it adds `/nix/store` to the read-only system paths, so a Nix binary can find its interpreter
    and libraries;
  - it skips hidden Nix store symlinks at the project root (`.mcp.json`, `.claude/settings.json`),
    because `bwrap` cannot mount over a symlink destination.
- The package is pinned to `clank-talk@0.1.3` and has no runtime `npx`.

## Limits

- OpenCode `plugin list` shows `-` for the folder plugin even when it loads. Use a
  `clank-opencode` session as the real check; a normal session keeps `execute`/`shell`, a guarded
  session shows only `clank_talk` (and `question`).
- The TUI commands (`/clank-talk on|off`, `/taint`) are loaded by the TUI part. They are not
  exercised by the headless `opencode run` smoke test.
- The MCP server is packaged (`clank-talk-mcp`) but is **not** in the MCP gateway. The native
  integrations are preferred; Pi has no MCP elicitation.
- Upstream is 0.1.3 and under construction. A bump can change the plugin API, the extension entry
  or the policy syntax. The pin is deliberate.

## Troubleshooting

| Symptom                                   | Check                                                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `clank_talk` is missing in OpenCode       | `KDN_CLANK_TALK=1`; the shim files are regular, not symlinks; run `clank-opencode`, not `opencode` |
| `clank_talk` is missing in Pi             | Run `clank-pi`; a plain `pi` does not load the extension                                           |
| A sandboxed tool says `bwrap` is missing  | `command -v bwrap`; enter the devshell                                                             |
| A sandboxed tool cannot exec a Nix binary | The package patch is missing; rebuild `.#clank-talk`                                               |
| `AGENTS.talk` has an error                | `clank-talk harness --json --root .` prints the parsed policy and its errors                       |
| The OpenCode plugin is stale              | `opencode reload`, or restart the private server; the service caches a failed module per path      |

## Files

| Path                                                 | Role                                                                   |
| ---------------------------------------------------- | ---------------------------------------------------------------------- |
| `packages/clank-talk/default.nix`                    | The pinned package and the NixOS sandbox patches                       |
| `modules/den/aspects/opencode.nix`                   | The den aspect: shim generation and the `clankTalk` option             |
| `modules/slots/opencode/default.nix`                 | The same option for slot consumers                                     |
| `devenv.nix`                                         | `clank-pi`, `clank-opencode`, `bubblewrap` (Linux) and the package pin |
| `AGENTS.talk`                                        | The policy: tools and hooks                                            |
| `.opencode/plugins/kdn-clank-talk/`                  | Generated shim (regular files, not tracked)                            |
| `.talk/audit/`, `.talk/harness/`, `.talk/untrusted/` | Audit, session state and tainted inputs                                |

## Related

- [ClankTalk docs for humans](https://clank.talk/docs.html) and
  [for agents](https://clank.talk/reference.html).
- [Pi harness](pi-harness.md) — the normal Pi wrapper and its extension inventory.
- [MCP setup](mcp-setup.md) — the gateway that does not carry ClankTalk.
