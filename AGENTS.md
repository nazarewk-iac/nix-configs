# AGENTS.md

AI Agent Guidance for nix-configs Repository.

## Topic Files

- [Version Control](.agents/rules/version-control.md) — `jj` workflow, checkpoints, push rules
- [Repository Structure](.agents/rules/repo-structure.md) — directory layout, host build commands
- [Module Architecture](.agents/rules/module-architecture.md) — context guards, `kdnConfig`, standard patterns, `kdn.env.*`
- [Nix Conventions](.agents/rules/nix-conventions.md) — formatting, module design principles (auto-loaded for `.nix` files)
- [Packaging Python Scripts](.agents/rules/packaging-python.md) — `init-py-script`, `mkPythonScript`, `default.nix` pattern
- [Flake Update](.agents/rules/flake-update.md) — update procedure, patch handling, testing (full doc: [docs/flake-update.md](docs/flake-update.md))
- [jj Workflows](.agents/rules/jj-workflows.md) — working copy, split, bookmark hygiene, fork rebase (full doc: [docs/jj-workflows.md](docs/jj-workflows.md))
- [MCP Setup](.agents/rules/mcp-setup.md) — gateway architecture, adding backends, mcpsnoop (full doc: [docs/mcp-setup.md](docs/mcp-setup.md))

## docs/ — full documentation

Human-readable docs live in `docs/`. Agent summaries in `.agents/rules/` are short pointers;
read the full doc when you need detail.

| Doc | Contents |
|---|---|
| [docs/flake-update.md](docs/flake-update.md) | Flake update procedure, commit structure, testing |
| [docs/flake-update.fork.md](docs/flake-update.fork.md) | Fork-specific update workflow (merge commit, flake-lock-merge) |
| [docs/jj-workflows.md](docs/jj-workflows.md) | jj patterns: working copy, split, squash, rebase |
| [docs/mcp-setup.md](docs/mcp-setup.md) | MCP gateway architecture, configuration, backends, lifecycle |
| [docs/mcpsnoop.md](docs/mcpsnoop.md) | mcpsnoop traffic inspector: setup, TUI usage, filtering, workflows |
| [docs/nix-dev.md](docs/nix-dev.md) | Nix development: building devenv shell, vendored lockfile recovery, hash updates |

## Nix Store Symlinks

> **Important:** Any file in this repo that is a symlink into `/nix/store/...` was placed
> there by one of:
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
- **In other repos** that import `devenvModules.default`: use that repo's own `devenv.nix`
  directly. Only promote something to `modules/slots/` when it genuinely needs to be reused
  across multiple repos — don't do it preemptively.

`.claude/settings.local.json` is a regular local file and can be edited directly.

## External Resources

- **NixOS**: https://nixos.org
- **Home Manager**: https://github.com/nix-community/home-manager
- **nix-darwin**: https://github.com/LnL7/nix-darwin
