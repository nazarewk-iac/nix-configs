---
type: Research
description: What okf-agent-memory does, how the OKF ecosystem handles writable memory and generated indexes, and why the integration should split a writable memory bundle from the read-only kdn-okf browser.
task: definition.md
authored_by: agent
timestamp: 2026-11-16T15:30:00+01:00
---

# Research: agent memory and the OKF ecosystem

## 1. `okf-agent-memory`

Repository: <https://github.com/okf-memory/okf-agent-memory>. MIT, Go, zero external dependencies.
First release 2026-09-05; v0.6.1 on 2026-10-12; roughly 800 GitHub stars by mid-October 2026.

It implements **Dual-Memory Agent Architecture (DMAA)**:

- **Push layer:** a compact `AGENTS.md` codex written in Agent Action Grammar (AAG), capped at a
  few hundred tokens. It holds invariants and triggers such as "search before write".
- **Pull layer:** an OKF v0.2 bundle (by convention `knowledge/`) that costs zero tokens until an
  agent queries it.

Commands:

| Command                                                                     | What it does                                                                                         |
| --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `validate [bundle] --strict --drift --scorecard --min-score N`              | Conformance, graph connectivity, description drift, quality scorecard and a CI gate                  |
| `search [query] [bundle] --for-path --filter --scope --stale-within --json` | In-memory BM25 over titles, descriptions, tags, IDs and bodies                                       |
| `show <id> [bundle] --raw --json`                                           | Frontmatter, body, inbound/outbound links and the resolved scope                                     |
| `create <id> [bundle] --type --title --desc --body --status --tags --actor` | Creates a concept and updates the parent `index.md` and dated `log.md`                               |
| `update <id> [bundle] ...`                                                  | Updates supplied fields and records the change in `log.md`                                           |
| `relate <source> <target> [bundle]`                                         | Adds a relative link between two concepts                                                            |
| `init [dir]`                                                                | Bare bundle: `index.md` with `okf_version: "0.2"` and `log.md`                                       |
| `bootstrap [dir]`                                                           | `knowledge/`, the `okf-memory` skill, `AGENTS.md`, tool symlinks and a `Makefile`                    |
| `mcp [bundle]`                                                              | stdio MCP server: `okf_search`, `okf_show`, `okf_create`, `okf_update`, `okf_relate`, `okf_validate` |
| `pull`/`restore`/`vendor`                                                   | Registry bundles, `okf.lock` with SHA-256 checksums, `.okf/vendor/`                                  |
| `hub init-vault/push/pull/sync/serve`                                       | Zero-knowledge encrypted sync with a CAS hub                                                         |

Scopes:

| Scope   | Location                         | Priority |
| ------- | -------------------------------- | -------- |
| project | `./knowledge/`                   | 100      |
| vendor  | `.okf/vendor/<bundle>/`          | 70       |
| user    | `~/.okf/` or `$OKF_USER_DIR`     | 50       |
| system  | `/etc/okf/` or `$OKF_SYSTEM_DIR` | 10       |

A higher layer shadows an identical concept ID in a lower one. The root `index.md` may declare
`scopes: [project, vendor]` to isolate a workspace; an empty or non-canonical list fails loading.

Caveats:

- Pre-1.0 with breaking flag changes (`--filter` aliases were removed in v0.6.0).
- The binary is named `okf`, the same name as `superops-team/okf` and one `okf-mcp` binary.
- DMAA, AAG, scope prefixes and `okf://` URNs are conventions on top of OKF that other tools do
  not understand.
- `bootstrap` writes `AGENTS.md`, `.agents/skills/okf-memory/`, tool symlinks and a `Makefile`; it
  hardcodes `knowledge/` and has no bundle-directory flag. `init` takes any directory.
- The hub/vault is a new security and supply-chain surface; it stays off.

## 2. How the ecosystem handles generated indexes

| Tool             | Approach                                                                                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| xMatrix          | Every directory has an `index.md`; the root declares `okf_version: "0.2"`; pages carry `generated.by`/`generated.at`. Git is the transport.                                                 |
| Roteiro          | A producer, consumer and validator in one Rust tool; `roteiro render okf` writes per-directory `index.md` and typed concepts.                                                               |
| okf-postgres     | Writes `index.md` plus a `.okf-producer.json` manifest with a SHA-256 digest per owned file. Re-runs remove only stale files whose digest still matches; hand-authored files are preserved. |
| okf-agent-memory | `create`/`update` maintain `index.md` and `log.md`; `--drift` detects a description that no longer matches its parent index listing.                                                        |
| kdn-okf          | `generate-index` writes a deterministic `index.md` per directory with a generated marker; refuses a human-authored file unless `--force`.                                                   |
| okf-mcp          | A producer host validates a candidate bundle and publishes it under an ownership manifest.                                                                                                  |

The strongest ownership model is okf-postgres: a manifest with a digest per owned file, so the
tool can tell "my stale file" from "a human edited this". The marker alone cannot.

## 3. Read-only and writable sides

The ecosystem splits cleanly:

- **Writable memory:** okf-agent-memory, OpenWiki, Inkeep, Groma, KL4A, okf-postgres.
- **Read-only consumption:** OKF-Runtime, W4G1/okf (TUI), Obsidian, kdn-okf.
- **Gates:** okflint (rules + profile), OKF-Schema (per-type JSON Schema), OKForest (28 rules),
  JidoSeal (trust grades), okf-guard (source safety before generation).

`kdn-okf` is a consumer, a TUI and a structural gate. Making it also the writer would duplicate
okf-agent-memory's bookkeeping and create two writers for one bundle.

## 4. Decision

- Use `okf-agent-memory` as the writable memory layer, with the bundle at `.agents/knowledge`.
- Add a root `knowledge -> .agents/knowledge` symlink so the default `./knowledge` and
  `--scope project` work from the repository root.
- Keep `kdn-okf` read-only for that bundle: list, show, search, outline, section, context, TUI and
  `doctor --parse-only`. Do not run `kdn-okf generate-index` on it.
- Expose the memory through the MCP gateway, read tools first.
- Gate with `okf-memory validate --strict --drift --min-score 80` and keep
  `kdn-okf doctor --parse-only` as the structural gate.
- Skip the registry, vendor/user/system scopes and the hub in v1.

## 5. Sources

- okf-agent-memory: <https://github.com/okf-memory/okf-agent-memory>
- CLI and MCP reference: <https://github.com/okf-memory/okf-agent-memory/blob/main/docs/guides/CLI.md>
- OKF ecosystem map: <https://okf.md/ecosystem-map/>
- OKF tools inventory: <https://okf.md/tools/>
- okf-postgres ownership manifest: <https://github.com/mfdaves/okf-postgres>
- xMatrix bundle layout: <https://github.com/LambdaLabsHQ/xmatrix>
- Roteiro producer/consumer/validator: <https://github.com/OffeneDatenmodellierung/Roteiro>
- OKF-Runtime consumer: <https://github.com/spomytkin/OKF-Runtime>
