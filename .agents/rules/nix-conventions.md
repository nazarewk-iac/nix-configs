---
paths:
  - "**/*.nix"
---

# Nix Conventions

Full development notes (building, lockfile recovery, hash updates): [docs/nix-dev.md](../../docs/nix-dev.md)

## Formatting

**Format all Nix files with `nixfmt`** before committing. Uses RFC-style `nixfmt` from nixpkgs, not `nixfmt-classic`. Use `nix run .#kdn-nix-fmt --` as a shortcut to format files in the repo.

## Devenv-managed files

Files installed by devenv slots (via `files.` or `enterShell` symlinks) are **not committed**.
They land in the working tree as symlinks to `/nix/store/...` or as generated files under
`hack/git/hooks/`. Always check `ls -la <path>` before editing — if it points to `/nix/store/`,
edit the source in `modules/slots/` instead.

Devenv-managed paths are gitignored explicitly in `.gitignore`. If a new slot installs a file
into a tracked directory (e.g. `.agents/rules/`, `hack/git/hooks/`), add it to `.gitignore`.

### Self-reference: `inputs.nix-configs` / `inputs.kdn-configs-src`

Slot modules under `modules/slots/*/default.nix` source `.agents/rules/*.md` and
`.agents/skills/*/SKILL.md` files via `"${inputs.nix-configs}/.agents/..."` — `inputs.nix-configs`
is declared in `devenv.yaml` as `url: path:.` (this repo, self-referential), and in `flake.nix`
the flake sets `nix-configs = self;` for the same purpose in `kdnMetaModule`. Existing usages:
`modules/slots/nix/default.nix`, `modules/slots/jj/default.nix`, `modules/slots/jj/fork/default.nix`,
`modules/slots/mcp/basic-memory/default.nix`.

`packages/*/default.nix` scripts (e.g. `aws-sso`, `flake-lock-merge`, `kdn-nix-fmt`,
`init-py-script/template`) use a differently-named but analogous self-reference,
`__inputs__.inputs.kdn-configs-src`, to locate `lib/python/mkPythonScript.nix` when building
outside this repo — falls back to `lib.kdn.mkPythonScript pkgs` when unset (i.e. when building
from within this repo itself).

**A just-created or just-edited file can be invisible to some Nix evaluations and not others** —
`devenv.yaml`'s `inputs.nix-configs = path:.` sees new files immediately (filtered only by
`.gitignore`), but `flake.nix`'s `nix-configs = self` — and anything reached via the CLI's `.#`
shorthand against `self` (host configs, `darwinConfigurations`/`nixosConfigurations`) — resolves
through a `git+file://` fetcher that reads git's tracked index, which jj does not always keep in
sync with `@` on every snapshot. See [jujutsu-vcs.md](../../docs/jujutsu-vcs.md)'s "Colocation
hazard" section for the full mechanism and empirical findings; when in doubt, check
`git ls-files -- <path>` before trusting a `.#`-based build of a just-touched file.

## Verifying changes

Prefer `devenv eval '<option.path>'` over a full `devenv build shell` when you only need to
confirm a specific option evaluates correctly (e.g. after wiring a new `claude.code.hooks.*` or
`claude.code.agents.*` entry) — it's much faster since it skips building derivations:

```bash
devenv eval 'claude.code.hooks.jj-guard'        # confirm a hook's command/matcher/hookType
devenv eval 'claude.code.agents.jj-expert.proactive'
```

Still run `devenv build shell` before declaring work done on anything that touches package
builds or derivation-level changes — `devenv eval`/`devenv build` alone only check evaluation,
not that packages actually compile. See [nix-dev.md](../../docs/nix-dev.md#building-and-testing).

## Option Declarations

**Prefer flat `foo.bar =` over nested `foo = { bar =`** everywhere — `options` declarations,
`config` assignments, and module consumer code. Nested attrset syntax is only appropriate when
setting multiple sibling keys at once and the grouping genuinely aids readability.

## Module Design

**All modules must be side-effect free by default** (enabled via `*.enable` options). The meta-module (`modules/meta/`) is the escape hatch for third-party modules that don't follow this pattern.

For full module architecture details see [module-architecture.md](module-architecture.md).
