---
type: Reference
description: Catalog of MCP gateway tools/backends in this repo's devenv, with safety and allow-listing recommendations.
timestamp: 2026-07-22T09:55:00+02:00
---

# MCP Gateway Tools Report

Snapshot of every tool reachable through `mcp-gateway` in this repo's devenv shell (see
[mcp-setup.md](mcp-setup.md) for the gateway architecture, [mcpsnoop.md](mcpsnoop.md) for how
this catalog was produced). Captured by test-running every backend, one representative call per
tool category, through mcpsnoop.

## Gateway meta-tools

These are the only tools Claude Code sees directly (~14, regardless of backend count):

| Tool | Role | Notes |
|---|---|---|
| `gateway_list_servers` | selector | Lists backends, status, circuit-breaker state. Safe, read-only. |
| `gateway_list_tools` | selector | Lists tools for one/all backends, with schemas. Safe, read-only. |
| `gateway_search_tools` | selector | Ranked keyword search over tool schemas. Safe, read-only. |
| `gateway_invoke` | **dispatcher** | Routes `(server, tool, arguments)` to a backend. All actual work funnels through this one tool name — see [Allow-listing limitation](#allow-listing-limitation) below. |
| `gateway_run_playbook` | action | Executes a named multi-step playbook. Not used by any backend here; no playbooks defined. |
| `gateway_get_profile` / `gateway_list_profiles` / `gateway_set_profile` | selector/action | Routing profiles (tool/backend allow-deny sets). No profiles are currently defined (`gateway_list_profiles` → empty); see [Routing profiles](#routing-profiles-unused) below. |
| `gateway_get_stats` / `gateway_cost_report` | selector | Invocation counts, latency, token/cost estimates. Safe, read-only. |
| `gateway_list_disabled_capabilities` / `gateway_reload_capabilities` | selector/action | Circuit-breaker introspection and capability-YAML hot-reload. Not relevant to this repo (no capability YAMLs defined). |
| `gateway_kill_server` / `gateway_revive_server` | action | Manual backend restart — used for reloading `.devenv/mcp-gateway.yaml` after a devenv rebuild without restarting the Claude Code session (see mcp-setup.md Lifecycle). |

## Backend tools

### jj (37 tools) — Jujutsu VCS

Read-only:

- `jj_status`
- `jj_log`
- `jj_diff`
- `jj_bookmark_list`
- `jj_op_log`
- `jj_obslog`
- `jj_workspace_list`
- `jj_config_get`
- `jj_tag_list`
- `jj_file_show`
- `jj_sanity_check`
- `jj_sparse` (list mode)

Mutating, low-risk:

- `jj_describe`
- `jj_commit`
- `jj_new`
- `jj_bookmark_create`
- `jj_git_fetch`
- `jj_git_import`
- `jj_undo`
- `jj_redo`
- `jj_prev`
- `jj_next`
- `jj_workspace_add`
- `jj_config_set` (repo scope)
- `jj_tag_create`
- `jj_init`
- `jj_bisect`

Mutating, destructive (all carry a `confirmed: true` gate and an explicit `⚠️` warning in their
own description — the backend implements its own confirmation step independent of Claude Code's
permission system):

- `jj_abandon`
- `jj_rebase`
- `jj_squash`
- `jj_split`
- `jj_edit`
- `jj_restore`
- `jj_bookmark_delete`
- `jj_git_push`
- `jj_git_export`
- `jj_sparse` (add/remove mode)
- `jj_config_set` (user scope)

**Gap vs. this repo's own conventions:** this jj-mcp backend duplicates some of what the CLI
already does, but per this repo's `jujutsu-vcs` skill and rules, agents in this repo are
expected to use the `jj` CLI directly (via Bash, allow-listed in
`modules/slots/jj/default.nix`), not this MCP backend — the CLI path is what's covered by the
`jj-guard` PreToolUse hook and the `jj-expert` subagent. Prior memory (`jj MCP gaps and CLI
fallback patterns`) also documents `jj_split` failing headlessly over MCP. Recommendation:
treat this backend as exploratory/secondary; don't add it to a trusted allow-list until the CLI
parity gaps are closed.

### devenv (8 tools)

Read-only:

- `list_processes`
- `get_process_status`
- `get_process_logs`
- `search_options`
- `search_packages`

Mutating, low-risk (process supervision only, no repo/file mutation):

- `start_process`
- `stop_process`
- `restart_process`

No destructive tools in this backend. Safe to allow broadly.

### memory-public / memory-sensitive (23 tools each) — basic-memory

Read-only:

- `read_content`
- `read_note`
- `view_note`
- `build_context`
- `recent_activity`
- `search_notes`
- `search`
- `list_directory`
- `list_memory_projects`
- `list_workspaces`
- `cloud_info`
- `release_notes`
- `schema_validate`
- `schema_infer`
- `schema_diff`
- `canvas`
- `fetch`

Mutating:

- `write_note`
- `edit_note`
- `move_note`
- `create_memory_project`

Destructive:

- `delete_note` (also deletes whole directories via `is_directory: true`)
- `delete_project`

Both instances expose an identical tool surface — the only difference is which knowledge base
they read/write (public vs. sensitive; see `.agents/rules/basic-memory.md` for routing rules).
The `kdn.mcp.pretty-print` PermissionRequest hook (see below) already replaces the native
approval dialog for `write_note`/`delete_note` on both, showing title/directory/identifier as
metadata fields with the raw note content as the dialog body.

### Backends declared but not enabled in this repo's `devenv.nix`

`filesystem`, `sequential-thinking`, `time`, `fetch`, `nixos` are supported by the `kdn.mcp`
slot (`modules/slots/mcp/default.nix`) but this repo only enables `filesystem` conditionally via
`kdn.nix.enable` → `nixos.enable`; as configured today only `jj`, `devenv`, `memory-public`,
`memory-sensitive` are live (confirmed via `gateway_list_servers`). Enabling more programs is a
one-line change in `kdn.mcp.programs.<name>.enable`.

## Allow-listing limitation

Claude Code's `permissions.allow`/`ask`/`deny` rules match on **tool name only** — there is no
syntax for matching against a specific argument value passed to an MCP tool (confirmed against
current Claude Code docs). Because every backend call funnels through the single dispatcher tool
`mcp__mcp-gateway__gateway_invoke(server, tool, arguments)`, Claude Code's own permission system
cannot distinguish "call jj_status" (read-only) from "call jj_git_push" (destructive) — both
look identical to the permission UI as one `gateway_invoke` call.

**What this repo does about it — three designs were tried, in order:**

1. **PreToolUse + `systemMessage`** (first attempt). A PreToolUse hook attached a readable
   preview via `hookSpecificOutput.systemMessage`, leaving `permissionDecision` unset so the
   normal allow/ask/deny flow proceeds untouched. Empirically, `systemMessage` renders only
   *after* the approval dialog resolves (as a `⎿ PreToolUse:<matcher> says: ...` annotation
   attached to the tool-call result), never inside the dialog itself before the user answers —
   so this didn't solve the actual problem (an unreadable dialog at decision time).
2. **`surfaced_tools`** (second attempt). mcp-gateway supports pinning specific backend tools
   directly in `tools/list` (`meta_mcp.surfaced_tools: [{server, tool}]`), bypassing the
   `gateway_invoke` dispatcher entirely — a surfaced tool would show its own real name/schema in
   the approval dialog. Confirmed the config schema against the gateway's own Rust source
   (`SurfacedToolConfig`, `MetaMcpConfig`) — our config was correct. But empirically unreliable:
   `resolve_surfaced_tool` requires the backend's tool cache to already be populated when the
   *first* `tools/list` is served, and stdio warm-start (`spawn_warm_start_task`) fires
   asynchronously right as the read loop starts — a race that appears to be lost every time on a
   fresh session, since backend subprocesses need real wall-clock time to spawn and respond.
   There's no config flag to block startup on warm-start completing. Abandoned.
3. **PermissionRequest + native Tk dialog** (shipped). `PermissionRequest` fires immediately
   before Claude Code would show its own approval dialog and can return `allow`/`deny` directly
   — when it does, Claude Code never renders its native dialog at all. `kdn.mcp.pretty-print`'s
   hook builds a readable preview (via the same per-backend plugin package as design 1) and
   shows it in a native Tk window (title + key/value metadata fields + plain-text body +
   Allow/Deny buttons), blocking until the user answers. Confirmed working live. This replaces —
   rather than customizes — the dialog, since no hook output field can rewrite the *native*
   dialog's own rendering of tool name/arguments (confirmed empirically and against current
   docs).

**Remaining lever not yet tried:** mcp-gateway's own `security.firewall.rules` — glob
`tool_match` patterns with `Allow`/`Warn`/`Block` actions, evaluated inside the gateway itself,
independent of any MCP client's permission UI. Would let e.g. `jj_git_push`/`jj_abandon`/
`delete_note` be hard-blocked or flagged at the gateway level regardless of which client connects.
Requires `security.firewall.enabled = true` plus a `rules` list in the generated YAML
(`modules/slots/mcp/default.nix`'s `gatewayConfig`) — not wired up yet. Worth pursuing if the
goal shifts from "readable approval" (solved) to "policy enforcement independent of the client."

## Routing profiles (unused)

`gateway_list_profiles` currently returns zero profiles (`{"default": "default", "profiles":
[], "total": 0}`). Profiles let a session restrict its visible tools/backends by name
(`gateway_set_profile`) — e.g. a "read-only" profile denying all mutating jj/basic-memory tools.
Not configured in `.devenv/mcp-gateway.yaml` today; would need a `profiles:` section in the
generated YAML plus a way to select one at session start. Lower priority than firewall rules
since it's session-scoped opt-in rather than an always-on backstop.

## Test coverage

Every live backend/tool category above was exercised end-to-end through mcpsnoop during this
report's preparation — see [mcpsnoop.md](mcpsnoop.md#testing-a-new-backendtool-surface) for the
repeatable procedure. Mutating calls were scoped to scratch data (throwaway `memory-public`
notes, created and deleted) or pure read-only introspection; no destructive jj operations,
`git_push`, or config mutations were exercised live, since jj-mcp's own `confirmed: true` gate
makes those a deliberate, separate decision (see jj-mcp gaps note in memory: "jj MCP gaps and CLI
fallback patterns").
