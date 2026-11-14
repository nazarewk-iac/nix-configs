---
type: Reference
description: Index of AI agent guidance topic files and docs for the nix-configs repository.
timestamp: 2026-07-09T15:32:54+02:00
---

# AGENTS.md

AI Agent Guidance for nix-configs Repository.

## Committing is expected, not requested

Commit as you go. The moment a piece of work is a self-contained change, carve
it out of `@` with `jj split -m 'msg' -- <files>`; fold a small fixup into the
changeset that introduced the line with `jj absorb -- <files>`. **Do this
proactively — do not wait for the user to explicitly ask you to commit.** Do not
let unrelated edits pile up in `@`. **Always list every file your session owns
on every path-taking jj command** (`split`, `squash`, `absorb`, `commit`,
`restore`, `status`, `diff`): other sessions may share `@`, and a path-less
command can sweep their work into your commit. See
[Jujutsu VCS](.agents/rules/jujutsu-vcs.md). Never push; the user reviews and
pushes.

**Always end with an unnamed `@` at the tip.** After your last commit, run
`jj new` so the working copy is a fresh, undescribed change. Never leave `@`
carrying a description: the next edit would silently join an already-described
change, and the user reviews from the tip. See
[Jujutsu VCS](.agents/rules/jujutsu-vcs.md).

## Keep a worklog and a board

Every run keeps a **session** worklog (append-only, dated) and board (current state) in
`.cache/agents/<harness>-<YYYYMMDD>-<session>/{worklog,board}.md` — the date between the harness
name and the harness session id, and the session id always present. A run that works in a task directory also
keeps the task pair, `<task-dir>/.{worklog,board}.md`: the session pair records the run, the task
pair records the task's history. Parallel tracks get one `board-<track>.md` each and append to the
shared worklog.

The user can switch the journals off. A direct "no worklog" instruction in the session wins;
`KDN_AGENT_WORKLOG=skip` is the scriptable fallback. See
[Worklog and Board](.agents/rules/agent-journal.md).

## Topic Files

- [Jujutsu VCS](.agents/rules/jujutsu-vcs.md) — jj mandate, working copy, split, bookmark hygiene, fork rebase (full doc: [docs/jujutsu-vcs.md](docs/jujutsu-vcs.md), fork topology: [docs/jujutsu-vcs.fork.md](docs/jujutsu-vcs.fork.md); short pointer also at [version-control.md](.agents/rules/version-control.md))
- [Repository Structure](.agents/rules/repo-structure.md) — directory layout, host build commands
- [Module Architecture](.agents/rules/module-architecture.md) — context guards, `kdnConfig`, standard patterns, `kdn.env.*`
- [Nix Conventions](.agents/rules/nix-conventions.md) — formatting, module design principles (auto-loaded for `.nix` files)
- [Slots Standalone](.agents/rules/slots-standalone.md) — slots must not reference or assign any `modules/universal`- or `modules/meta`-declared option inside their own target configs (full architecture: [modules/slots/README.md](modules/slots/README.md))
- [Packaging Python Scripts](.agents/rules/packaging-python.md) — `init-py-script`, `mkPythonScript`, `default.nix` pattern
- [Forking and vendoring](.agents/rules/forking.md) — fork into nazarewk-iac, one jj bookmark per patch joined into `main`, vendor by pinned rev+hash (general guide: [docs/guides/git-forking.md](docs/guides/git-forking.md); Pi specifics: [docs/pi-extension-forks.md](docs/pi-extension-forks.md))
- [Flake Update](.agents/rules/flake-update.md) — update procedure, patch handling, testing (full doc: [docs/flake-update.md](docs/flake-update.md))
- [MCP Setup](.agents/rules/mcp-setup.md) — gateway architecture, adding backends, mcpsnoop (full doc: [docs/mcp-setup.md](docs/mcp-setup.md))
- [Tasks](.agents/rules/tasks.md) — one directory per task at `docs/tasks/<YYYY-MM>/<slug>/`, recursive sub-tasks, done-tag + sibling solution file; a work-run status belongs in the task's `.worklog.md` (full doc: [docs/tasks/README.md](docs/tasks/README.md))
- [Worklog and Board](.agents/rules/agent-journal.md) — every agent run keeps a session `{worklog,board}.md` (`.cache/agents/<harness>-<YYYYMMDD>-<session>/`, date then the mandatory session id) plus a task pair when a task exists; one board per parallel track; a direct "no worklog" instruction or `KDN_AGENT_WORKLOG=skip` turns them off
- [kdn-journal](.agents/rules/kdn-journal.md) — agent-facing use of the task/journal CLI: JSON reads, explicit session and root, `doctor --parse-only` as the gate, and `task set-status` as the only write (full doc: [docs/kdn-journal.md](docs/kdn-journal.md#for-agents))
- [Post-change Checks](.agents/rules/post-change-checks.md) — check by blast radius (bundles, never a bare `nix flake check`), prove both harnesses load, build/activate/verify hosts, boot check supervised, skip or defer on request (full doc: [docs/post-change-checks.md](docs/post-change-checks.md))
- [Simple Technical English](.agents/rules/simple-technical-english.md) — strict ASD-STE100 for all docs, code comments, and chat; domain-vocabulary exception; ask the user before you drop STE
- [Darwin Quirks](.agents/rules/darwin-quirks.md) — on macOS, surface an unpredicted behaviour to the user, then record it in [docs/darwin-quirks.md](docs/darwin-quirks.md) after confirmation

## docs/ — full documentation

Human-readable docs live in `docs/`. Agent summaries in `.agents/rules/` are short pointers;
read the full doc when you need detail.

| Doc                                                                                                       | Contents                                                                                                                                                                                                                                                                |
| --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [docs/tasks/2026-09/generalization/](docs/tasks/2026-09/generalization/definition.md)                     | Umbrella task: make the modules reusable by an external adopter. It indexes the numbered sub-tasks in the same directory.                                                                                                                                               |
| [docs/tasks/2026-10/gaz-den-workstation/](docs/tasks/2026-10/gaz-den-workstation/definition.md)           | Umbrella task: convert `gaz` (Lenovo C13 Yoga) from a Crostini VM to a den NixOS workstation, driven by a supervised local-LLM fleet. Holds the personas, the harness design, and the fleet evaluation. Blocked on CR50/SuzyQ firmware write-protect.                   |
| [docs/tasks/2026-10/minipc-den-host/](docs/tasks/2026-10/minipc-den-host/definition.md)                   | The same harness and the same evaluation applied to a new x86 mini-PC (etra-style host, SFP uplink, headless over a NanoKVM). Mostly covers the purposes of the `gaz` task and has no hardware blocker, so it runs first.                                               |
| [docs/tasks/2026-10/location-aware-builders/](docs/tasks/2026-10/location-aware-builders/definition.md)   | Location-aware remote builders: prefer `brys` on the LAN, build locally when away, degrade to local instead of failing. Source-verified research on Lix builder semantics.                                                                                              |
| [docs/tasks/2026-10/pryll-mother-desktop/](docs/tasks/2026-10/pryll-mother-desktop/definition.md)         | The third host run of the same harness: the mother's KDE desktop for user `bn` on a LAN-connected mini-PC, with autologin, unattended updates, remote support and backups. No hardware blocker.                                                                         |
| [docs/den-for-adopters.md](docs/den-for-adopters.md)                                                      | den aspects for an external adopter: the 21 aspects, four worked examples, the priority rule, 10 caveats, the lock cost                                                                                                                                                 |
| [docs/slots-for-adopters.md](docs/slots-for-adopters.md)                                                  | The older `modules/slots` route for an external adopter: `mkSlots`, the packages overlay, what a slot writes into your repo                                                                                                                                             |
| [docs/den-universal-mapping.md](docs/den-universal-mapping.md)                                            | One row per `modules/universal` module: the `kdn.*` prefix it declares, its `modules/den/aspects` counterpart, and a port status. Plus the reverse list, the known gaps, and the commands that refresh every count.                                                     |
| [docs/tasks/2026-09/eval-performance/research.md](docs/tasks/2026-09/eval-performance/research.md)        | Evaluation-time profiling: Lix has no eval profiler, a CppNix client against the Lix daemon does. One real flamegraph of host `anji`, the top cost centres, and the protocol for a fair universal-versus-den comparison.                                                |
| [docs/tasks/2026-09/eval-performance/design.md](docs/tasks/2026-09/eval-performance/design.md)            | The design that follows that research: `hack/eval-profile.sh` reproduces a profile in one command, `hack/eval-compare.sh` holds the parity-gated tree comparison, and one lever collapses 205 den library evaluations into one. Each part carries an acceptance number. |
| [docs/tasks/2026-11/gc-category-retention/](docs/tasks/2026-11/gc-category-retention/definition.md)       | Store GC that keeps the newest build per class: angrr class policies, a namespaced category gcroot, an enqueue-only post-build hook, and an eBPF open-event observer feeding SQLite for true last-use LRU. Records why fs-atime cannot be used here.                    |
| [docs/tasks/2026-11/okf-browser/](docs/tasks/2026-11/okf-browser/definition.md)                           | General-purpose OKF v0.2 indexer and TUI: bundles, concepts, types/tags, links/backlinks, trust, freshness, doctor and JSON. Includes research on `zk`, `nb`, `glow` and Obsidian-style vault tools.                                                                    |
| [docs/tasks/2026-11/journal-session-identity/](docs/tasks/2026-11/journal-session-identity/definition.md) | Tie harness sessions to jj change IDs and Atuin Threads: local session sidecar, env-var detection for opencode/Pi/Claude/Codex, optional commit trailers, and `atuin threads --style json`.                                                                             |
| [docs/flake-update.md](docs/flake-update.md)                                                              | Flake update procedure, commit structure, testing                                                                                                                                                                                                                       |
| [docs/flake-update.fork.md](docs/flake-update.fork.md)                                                    | Fork-specific update workflow (merge commit, flake-lock-merge)                                                                                                                                                                                                          |
| [docs/jujutsu-vcs.md](docs/jujutsu-vcs.md)                                                                | jj patterns: working copy, split, squash, rebase, and the full `jj workspace` convention                                                                                                                                                                                |
| [docs/jujutsu-vcs.fork.md](docs/jujutsu-vcs.fork.md)                                                      | jj fork topology: dual-parent `@`, bookmark hygiene, rebasing the fork merge                                                                                                                                                                                            |
| [docs/vcs-workspaces.md](docs/vcs-workspaces.md)                                                          | Two hazards that bite _after_ setup in a sibling jj workspace: inherited `$DEVENV_ROOT`, untracked build inputs                                                                                                                                                         |
| [docs/mcp-setup.md](docs/mcp-setup.md)                                                                    | MCP gateway architecture, configuration, backends, lifecycle                                                                                                                                                                                                            |
| [docs/mcpsnoop.md](docs/mcpsnoop.md)                                                                      | mcpsnoop traffic inspector: setup, TUI usage, filtering, workflows                                                                                                                                                                                                      |
| [docs/kdn-journal.md](docs/kdn-journal.md)                                                                | The `kdn-journal` Go CLI and TUI: commands, board format, JSON envelope, exit codes, editor integration                                                                                                                                                                 |
| [docs/nix-dev.md](docs/nix-dev.md)                                                                        | Nix development: building devenv shell, vendored lockfile recovery, hash updates                                                                                                                                                                                        |
| [docs/nixos-containers.md](docs/nixos-containers.md)                                                      | Running an auxiliary service as a confined NixOS container: the private-network + socat-ingress pattern, the two-firewall trap, `sys/state` vs `sys/cache` buckets, the `mkIf` vs `optionalAttrs` failure, and how to activate a host that has no checkout              |
| [docs/rosec.md](docs/rosec.md)                                                                            | The rosec Secret Service: the fork and its native sops provider, the two store modes, the derived unlock-once identity, the module options in both trees, how to update the fork and the input, the conflict workflow, and the KeePassXC migration                      |
| [docs/darwin-quirks.md](docs/darwin-quirks.md)                                                            | General macOS-only behaviours: Full Disk Access on external volumes, the locked login keychain over SSH, encrypted APFS locking on unmount, launchd WorkingDirectory                                                                                                    |
| [hosts/anji/disks.md](hosts/anji/disks.md)                                                                | The `anji` external volumes: UUIDs, mount paths, unlock procedure, Full Disk Access for the builder, boot auto-unlock                                                                                                                                                   |
| [hosts/anji/bootstrap.md](hosts/anji/bootstrap.md)                                                        | Non-default macOS settings on `anji` outside Lix and nix-darwin: hostname, locale, FileVault, SSH, firewall, power, Full Disk Access, users, and how to reproduce each                                                                                                  |
| [docs/guides/git-forking.md](docs/guides/git-forking.md)                                                  | Fork a repository with the GitHub CLI, rename the remotes, and disable unused repository features                                                                                                                                                                       |
| [docs/tasks/README.md](docs/tasks/README.md)                                                              | Tasks convention: one directory per task under `<YYYY-MM>/`, done-tag + sibling solution, frontmatter schema                                                                                                                                                            |
| [checks/README.md](checks/README.md)                                                                      | Every check: its bundle, its measured time and its exact standalone command. Never run a bare `nix flake check` — it takes 11 minutes.                                                                                                                                  |

## Nix Store Symlinks

> **Important:** Any file in this repo that is a symlink into `/nix/store/...` was placed
> there by one of:
>
> - **devenv** (`modules/slots/*/default.nix` via `files.` or `enterShell`) — active only
>   inside a devenv shell
> - **NixOS / nix-darwin** system activation — managed by the host configuration
> - **Home Manager** — managed by the user's HM configuration
>
> Do NOT commit or modify these symlinks manually. They are regenerated on the next
> `devenv shell` / `darwin-rebuild switch` / `nixos-rebuild switch`.
>
> **Before editing any file** (especially `.claude/settings.json`, `.mcp.json`, or anything
> under `.claude/`): run `ls -la <path>` first. If it is a symlink into `/nix/store/`, find
> the source file in `modules/slots/` and edit that instead.

## Claude Settings

`.claude/settings.json` is managed by devenv (symlink into `/nix/store/`). **Never edit it
directly.** To change Claude Code settings (permissions, MCP servers, hooks):

- **In this repo:** edit the source in `modules/slots/` — large enough changes may warrant a
  new topic-specific slot module (e.g. `modules/slots/claude/`)
- **In other repos** that import via `inputs.nix-configs.mkSlots {...}`: use that repo's own
  `devenv.nix` directly. Only promote something to `modules/slots/` when it genuinely needs to
  be reused across multiple repos — don't do it preemptively.

`.claude/settings.local.json` is a regular local file and can be edited directly.

## External Resources

- **NixOS**: https://nixos.org
- **Home Manager**: https://github.com/nix-community/home-manager
- **nix-darwin**: https://github.com/LnL7/nix-darwin
