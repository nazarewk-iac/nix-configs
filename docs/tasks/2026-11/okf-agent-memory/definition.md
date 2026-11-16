---
type: Task
description: Integrate okf-agent-memory as the writable, git-native agent memory layer: bundle at .agents/knowledge behind a root knowledge symlink, MCP gateway backend, validation gate and agent rules, with kdn-okf as the read-only browser.
status: open
authored_by: agent
timestamp: 2026-11-16T15:30:00+01:00
---

# Integrate `okf-agent-memory` as the writable agent memory layer

## Context

`kdn-okf` reads, searches and validates OKF v0.2 bundles, but it is read-only: its one writer,
`generate-index`, only refreshes directory listings. Agents still lose decisions between sessions:
the task tree records what was done, not the invariants and decisions an agent needs before it
edits a file.

`okf-agent-memory` (`github.com/okf-memory/okf-agent-memory`) is a Go CLI and MCP server for
git-native project memory on OKF v0.2. It owns a writable bundle, maintains `index.md` and
`log.md` on `create`/`update`, searches with in-memory BM25, binds decisions to source files with
`code_refs`, validates graph connectivity and description drift, and exposes the memory to agents
over MCP.

The two tools overlap but do not compete:

- `okf-agent-memory` owns the **writable memory bundle** and its MCP server.
- `kdn-okf` stays the **read-only browser, TUI and structural validator** for any bundle.

The ecosystem shows the same split elsewhere: xMatrix and Roteiro generate per-directory
`index.md`, okf-postgres keeps an ownership manifest with a SHA-256 per generated file and
preserves hand-authored files, and okf-mcp separates validation from producer writes. See
[research.md](research.md).

## Goal

One committed memory bundle at `.agents/knowledge`, reachable through a root `knowledge` symlink,
written only by `okf-agent-memory`, read by `kdn-okf`, exposed to agents over the MCP gateway, and
gated by a check.

## Scope

### 1. Layout

- Real bundle: `.agents/knowledge/` (`index.md`, `log.md`, concepts).
- Root symlink: `knowledge -> .agents/knowledge`, so the tool's default `./knowledge` and
  `--scope project` resolve from the repository root.
- Root `index.md` declares `okf_version: "0.2"` and `scopes: [project]` for v1.
- The default bundle path is `./knowledge` or `.` relative to the current directory. From the
  repository root the symlink makes the default work; from a subdirectory the caller passes the
  path or runs from the root.
- Do not create a second bundle; do not point `generate-index` at this directory.

### 2. Package and binary

- `packages/okf-agent-memory/default.nix`, pinned to a release tag and a `vendorHash`.
- Binary name `okf-memory` (a wrapper or `mainProgram` rename). Upstream installs `okf`, which
  collides with `superops-team/okf` and one `okf-mcp` binary.
- Expose it in `devenv.nix`; install it in the Home Manager user profile and the den
  `program-kdn-tools` aspect, next to `kdn-journal`, `kdn-jj-meta` and `kdn-okf`.
- Pin a version; the project is pre-1.0 and changes flags between releases.

### 3. MCP

- Add `okf-memory` to the MCP gateway with `okf-memory mcp <abs path>/.agents/knowledge`.
- Expose `okf_search`, `okf_show`, `okf_create`, `okf_update`, `okf_relate`, `okf_validate`.
- Read tools are open to every agent. Write tools (`create`, `update`, `relate`) are disabled in
  v1 and enabled after the seed review, or gated to a memory-writing role.
- The gateway stays the only MCP entry point; no per-harness stdio config.

### 4. Agent rules

- New `.agents/rules/okf-memory.md`: search before write, one concept per decision, one-sentence
  `description`, `code_refs` for constraints, no secrets, no session transcripts, no duplicated
  rules that already live in `AGENTS.md`.
- Install the upstream `okf-memory` skill through the package (`share/okf-agent-memory/skill`)
  and link it in Home Manager for generic agents, opencode and pi, like the `kdn-*` skills. The
  repository carries the rule; the skill is the upstream procedure.
- `AGENTS.md` points at the rule; `kdn-okf` remains the reader.

### 5. Seed concepts

Start with the decisions agents keep rediscovering:

- `decisions/no-push` — the user reviews and pushes.
- `decisions/path-scoped-jj` — every path-taking jj command lists the session's files.
- `decisions/one-writer-per-bundle` — `okf-agent-memory` writes `.agents/knowledge`; `kdn-okf`
  does not.
- `decisions/cache-outside-bundle` — `kdn-okf` caches in the XDG cache.
- `decisions/trailer-profiles` — `Assisted-by`/`Generated-by`/`Session-Id`.
- `runbooks/` for a procedure that is repeated.

Each concept is short, carries `code_refs` when it governs a path, and is reviewed before merge.

### 6. Validation and checks

- `okf-memory validate .agents/knowledge --strict --drift` is the memory gate. The scorecard is
  reported; `--min-score 80` waits until a human verifies the seed.
- Add `okf-memory-validate` to `checks/default.nix` and `bundle-pkgs`.
- `kdn-okf doctor --parse-only --bundle .agents/knowledge` remains the structural gate; both run.
- `index.md` and `log.md` are owned by `okf-agent-memory`; `kdn-okf generate-index` is not run on
  this bundle.

### 7. AI-XF Level 2

- Every concept carries a stable slug `id` and typed `links` mirrored by a body link.
- `manifest.ai-xf.yaml` declares `ai-xf: "0.5"` and the bundle name.
- `ai-xf-validate .agents/knowledge --level 2` is the AI-XF gate; `okf-memory update` must
  preserve `id` and `links`.
- Level 3 (federation) is out of scope.

### 8. Security and scope

- v1 uses `scopes: [project]`; no vendor registry, user or system layers.
- The hub/vault (zero-knowledge sync) stays off; it is a new security and supply-chain surface.
- No secrets, credentials, customer data or session transcripts in the bundle.
- `code_refs` point at repository paths; no absolute paths.

## Non-goals

- Replacing `kdn-okf` or `kdn-journal`.
- Auto-exporting every journal session into memory.
- Registry/vendor bundles, user/system scopes, hub sync, paid certificates.
- A web UI or a second TUI.

## Acceptance

- `okf-memory init` created `.agents/knowledge`, the `knowledge` symlink resolves, and
  `okf-memory validate .agents/knowledge --strict --drift` exits 0 on the seed.
- `okf-memory mcp .agents/knowledge` is a gateway backend; `okf_search`/`okf_show` work from
  opencode and pi, and a write tool is either disabled or gated by the rule.
- `kdn-okf --bundle .agents/knowledge list --json` and `kdn-okf --bundle .agents/knowledge tui`
  read the same bundle.
- `okf-memory-validate`, `ai-xf-validate` and `kdn-okf doctor --parse-only` pass in the sandbox.
- `okf-memory` and its skill are installed by Home Manager and the den aspect.
- Docs: `docs/okf-memory.md`, `.agents/rules/okf-memory.md`, `AGENTS.md` rows.
- No secrets, no transcripts, no registry, no hub.

## Open questions

1. Pin which release (v0.6.1 at the time of writing, or the latest at implementation).
2. Binary name: `okf-memory` wrapper vs a patched `mainProgram`.
3. Symlink vs explicit paths: is the root `knowledge` symlink acceptable, or do we keep explicit
   `.agents/knowledge` paths and skip `--scope project`?
4. Write tools: disabled in v1 or enabled for a memory-writing role?
5. Which concepts seed the bundle, and who reviews them?
6. Do we install the upstream skill verbatim or adapt it to this repository's rules?
7. Is the registry/lockfile worth adopting for shared bundles later?
