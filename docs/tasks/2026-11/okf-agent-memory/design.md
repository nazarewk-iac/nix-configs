---
type: Design
description: Layout, packaging, MCP gateway wiring, agent rules, validation checks and seed strategy for integrating okf-agent-memory at .agents/knowledge with kdn-okf as the read-only browser.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T15:30:00+01:00
---

# Design: `okf-agent-memory` integration

## 1. Decisions

| Question        | Decision                                                 | Reason                                                                                                       |
| --------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Bundle location | `.agents/knowledge/`, real files                         | `.agents/` is already the agent metadata tree and is tracked.                                                |
| Default path    | Root symlink `knowledge -> .agents/knowledge`            | The tool's default is `./knowledge`; the symlink also makes `--scope project` work from the repository root. |
| Writer          | `okf-agent-memory` only                                  | It maintains `index.md`/`log.md`; a second writer would fight it.                                            |
| Reader          | `kdn-okf`                                                | TUI, outline/section/context, trust/staleness facets and `doctor --parse-only`.                              |
| Binary          | `okf-memory`                                             | Upstream installs `okf`, which collides with two other tools.                                                |
| Scopes          | `[project]`                                              | Vendor, user and system layers are a later decision; the hub is off.                                         |
| MCP             | Read tools first                                         | `okf_search`/`okf_show` are safe; writes need a role and a review.                                           |
| Gate            | `validate --strict --drift` + `ai-xf-validate --level 2` | Catches broken links, orphans, drift, missing ids and unmirrored typed links.                                |
| Seed            | A small curated set                                      | The memory must be trustworthy before agents write to it.                                                    |

## 2. Layout

```
repo/
├── knowledge -> .agents/knowledge      # symlink, tracked
├── .agents/
│   ├── knowledge/
│   │   ├── index.md                    # okf_version: "0.2", scopes: [project]
│   │   ├── log.md                      # maintained by okf-agent-memory
│   │   ├── decisions/
│   │   │   ├── no-push.md
│   │   │   └── path-scoped-jj.md
│   │   └── runbooks/
│   ├── rules/okf-memory.md
│   └── skills/okf-memory/SKILL.md
```

The default bundle path is `./knowledge` or `.`, relative to the current directory. From the
repository root the symlink makes `./knowledge` resolve to `.agents/knowledge`; without the
symlink the tool would fall back to `.` and treat the whole repository as a bundle. From a
subdirectory, pass the path or run from the root. `--scope project` is `./knowledge/`, so it also
needs the symlink.

`kdn-okf` does not follow the symlink in a walk (it skips directory symlinks), so it is always
pointed at the real path: `kdn-okf --bundle .agents/knowledge …`.

## 3. Package

```
packages/okf-agent-memory/
├── default.nix      # buildGoModule, pinned rev + vendorHash
└── ...
```

- Pin a release tag (v0.6.1 at the time of writing, or the latest at implementation) and record
  the `rev` and `hash`.
- `mainProgram = "okf-memory"`: rename the binary in `postInstall`, or wrap it. A wrapper is safer
  because upstream help text still says `okf`.
- Shell completions only if upstream ships them; otherwise skip.
- `passthru.tests.go-test` if upstream's Go tests run in the sandbox; otherwise the check is the
  bundle validation.
- Expose in `devenv.nix`; add to `home.packages` in the universal profile and to the den
  `program-kdn-tools` aspect.

## 4. MCP gateway

Add one backend to the existing gateway:

```json
{
  "okf-memory": {
    "command": "/run/current-system/sw/bin/okf-memory",
    "args": ["mcp", "/home/kdn/dev/github.com/nazarewk-iac/nix-configs/.agents/knowledge"]
  }
}
```

- v1 exposes read tools only: `okf_search`, `okf_show`, `okf_validate`.
- `okf_create`, `okf_update` and `okf_relate` are enabled after the seed review, or only for an
  agent role that is allowed to write memory.
- The gateway is the only entry point; no per-harness stdio configuration.
- The backend is optional: a host without the bundle still starts the gateway.

## 5. Agent rules and skill

`.agents/rules/okf-memory.md`:

- **Search before write.** Call `okf_search` or `okf-memory search` before creating a concept.
- **One concept per decision.** A concept has one `type`, one sentence of `description`, and a
  short body.
- **Bind constraints to code.** A rule about a path carries `code_refs`; query it with
  `--for-path` before editing.
- **No secrets, no transcripts, no personal data.** Memory is committed.
- **Do not duplicate `AGENTS.md`.** The push layer stays small; the bundle holds the detail.
- **`okf-memory` owns `index.md`/`log.md`.** Do not hand-edit them; use `create`/`update`.
- **`kdn-okf` reads, never writes this bundle.** `generate-index` is for documentation bundles.

The upstream `okf-memory` skill is installed by the package at `share/okf-agent-memory/skill`
and linked in Home Manager into `~/.agents/skills`, `~/.config/opencode/skills` and
`~/.pi/agent/skills`, next to the `kdn-*` skills. The repository carries the rule; the skill is the
upstream procedure.

## 6. Checks

- `okf-memory-validate` in `checks/default.nix`:
  - copy `.agents/knowledge` into the sandbox;
  - run `okf-memory validate "$TMPDIR/knowledge" --strict --drift`;
  - run `kdn-okf --bundle "$TMPDIR/knowledge" doctor --parse-only`;
  - join `bundle-pkgs`.
- The bundle is small, so the check is fast.
- `--strict` treats broken links and orphans as errors; `--drift` compares descriptions against
  the generated listings.
- Do not run `kdn-okf generate-index` in the check.
- Run `ai-xf-validate "$TMPDIR/knowledge" --level 2` as the AI-XF gate. The concepts carry a
  stable slug `id`, typed `links` mirrored by the body links, and `manifest.ai-xf.yaml` declares
  the version. Level 3 (federation) is out of scope.

## 7. Seed and migration

1. `okf-memory init .agents/knowledge`.
2. Create the root `index.md` frontmatter (`okf_version: "0.2"`, `scopes: [project]`) if `init`
   did not.
3. Add the seed concepts with `okf-memory create`, one per decision:
   - `decisions/no-push`
   - `decisions/path-scoped-jj`
   - `decisions/one-writer-per-bundle`
   - `decisions/cache-outside-bundle`
   - `decisions/trailer-profiles`
   - `runbooks/…` only where a procedure repeats.
4. Run `validate --strict --drift --scorecard`, review the output, then add the symlink.
5. Enable the MCP read tools; enable writes after a review of the first concepts.
6. Do not run `okf bootstrap` over this repository's `AGENTS.md`; use `init` and the rule file.

## 8. Security

- `scopes: [project]`; no vendor, user or system layers in v1.
- No registry, no `okf.lock`, no hub/vault in v1. Those are a separate supply-chain decision.
- No secrets, credentials, customer data or session transcripts.
- `code_refs` are repository-relative; no absolute paths.
- The MCP write tools are off until the seed is reviewed.
- The bundle is committed, so every change is reviewable with `git diff`.

## 9. Acceptance mapping

| Acceptance         | Evidence                                                                                  |
| ------------------ | ----------------------------------------------------------------------------------------- |
| Bundle and symlink | `okf-memory validate .agents/knowledge --strict --drift` from the root; `ls -l knowledge` |
| MCP                | `okf_search`/`okf_show` from opencode and pi through the gateway                          |
| Reader             | `kdn-okf --bundle .agents/knowledge list --json`, `tui`                                   |
| Checks             | `okf-memory-validate`, `kdn-okf doctor --parse-only`                                      |
| Install            | Home Manager `home.packages` and the den aspect list `okf-memory` and the skill           |
| Docs               | `docs/okf-memory.md`, `.agents/rules/okf-memory.md`, `AGENTS.md`                          |

## 10. Open questions

1. Pin which release, and how to keep it current (manual bump vs a flake input).
2. Wrapper vs `postInstall` rename for `okf-memory`.
3. Is the root symlink acceptable, or do we keep explicit paths and skip `--scope project`?
4. Write tools: off in v1, or a memory-writing role from the start?
5. Which seed concepts, and who reviews the first batch?
6. Does the upstream skill need changes for this repository's rules?
7. Later: registry/vendor bundles, or stay project-only?
