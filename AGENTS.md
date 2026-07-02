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

## External Resources

- **NixOS**: https://nixos.org
- **Home Manager**: https://github.com/nix-community/home-manager
- **nix-darwin**: https://github.com/LnL7/nix-darwin
