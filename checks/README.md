---
type: Reference
title: Checks — bundles and standalone commands
description: Every check, its bundle, its measured time and its exact standalone command.
authored_by: agent
timestamp: 2026-09-11T00:00:00Z
---

# Checks

**Do not run a bare `nix flake check`.** It builds all 38 checks of this system and takes over
**660 s** — 11 minutes on a warm store. Four checks cost over a minute each, and
`jj-experiments-pytest` alone runs 188 s. Run a bundle instead.

## Bundles

One command per bundle; nix builds the members in parallel. Swap `aarch64-darwin` for `x86_64-linux` or
`aarch64-linux` on those systems.

```bash
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-core'      # 16.7 s, after any edit
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-den'       # ~35 s, modules/den/aspects/
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-pkgs'      # 18.0 s, packages/
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-artifact'  # 43.7 s, a built artifact
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-slow'      # ~383 s, before a hand-off
```

`bundle-core` is the broad tripwire: the plumbing, the standalone rule and the cross-cutting set. Run it
first. `bundle-den` holds one assertion set per den aspect. Every non-VM bundle stays under 60 s;
`bundle-slow` and `bundle-vm` are the two exceptions, and `bundle-vm` is reserved and empty because no
VM test exists yet. `bundle-artifact` holds the 43.7 s only with the system closure already in the
store, and it is empty on `aarch64-linux`, which carries no `den-artifact-*` and no `den-smoke-*`.

## Every check

Measured 2026-09-11 on `aarch64-darwin`, warm store, one check per invocation. Slowest first. Set `SYS`
first: `SYS=aarch64-darwin` — or `x86_64-linux`, or `aarch64-linux`.

| Check | Proves | Bundle | Sec | Standalone command |
|---|---|---|---|---|
| `jj-experiments-pytest` | the isolated 3-repo jj suite, headless | slow | 188.4 | `nix build --no-eval-cache -L ".#checks.$SYS.jj-experiments-pytest"` |
| `den-eval-routes` | `denLib.imports` and `denModules` give one `drvPath` | slow | 83.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-routes"` |
| `den-mvp` | the whole parallel den tree evaluates and builds | slow | 75.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-mvp"` |
| `den-eval-instantiate` | every (aspect, class) pair forces its target module body | slow | 58.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-instantiate"` |
| `den-artifact-host-darwin` | the darwin toplevel holds the nix.conf lines and the plist | artifact | 46.7 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-artifact-host-darwin'` |
| `den-smoke-devenv-darwin` | the shell's own `enterTest` really runs | artifact | 18.9 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-smoke-devenv-darwin'` |
| `zellij-llm-pytest` | the `zellij-llm` package's own pytest suite | pkgs | 17.1 | `nix build --no-eval-cache -L ".#checks.$SYS.zellij-llm-pytest"` |
| `den-eval-frozen-paths` | no backend freezes an environment value | core | 5.6 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-frozen-paths"` |
| `kdn-slug-pytest` | the `kdn-slug` package's own pytest suite | pkgs | 4.5 | `nix build --no-eval-cache -L ".#checks.$SYS.kdn-slug-pytest"` |
| `den-eval-mcp` | one gateway per shell, every backend name in the YAML | den | 4.5 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-mcp"` |
| `hello` | the `checks.<system>` plumbing builds end to end | core | 4.3 | `nix build --no-eval-cache -L ".#checks.$SYS.hello"` |
| `den-eval-jj` | the repo config, the aliases, both hooks and the allowlist | den | 4.2 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-jj"` |
| `den-eval-ssh-access` | both halves of the aspect, and the empty-graph branch | den | 4.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-ssh-access"` |
| `den-artifact-hm-host-darwin` | the forwarded generation writes all three shell hooks | artifact | 4.0 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-artifact-hm-host-darwin'` |
| `den-artifact-home-darwin` | the same, for the standalone home-manager route | artifact | 3.6 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-artifact-home-darwin'` |
| `den-eval-signing` | git and jj read one identical `allowed_signers` file | den | 3.5 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-signing"` |
| `den-eval-devenv-cli` | the full matrix over four classes and both home routes | den | 3.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-devenv-cli"` |
| `den-eval-nix` | the pre-commit hook, and the `$DEVENV_ROOT` expansion | den | 3.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-nix"` |
| `den-eval-nix-config` | the nine `nix.conf` options, both list traps, the 18 builder leaves | den | ‡ | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-nix-config"` |
| `den-eval-ssh-agent` | the user scope alone, and the platform split | den | 2.6 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-ssh-agent"` |
| `den-eval-gh` | the package, the opt-in, and no mutating rule in the allowlist | den | 2.5 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-gh"` |
| `den-eval-llm` | each aspect of the family resolves for its own class | den | 2.5 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-llm"` |
| `den-eval-zellij` | the skill file, both hooks, both source-repo branches | den | 2.5 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-zellij"` |
| `standalone-slots` | no slot names a universal option, a meta option or `kdnConfig` | core | 2.3 | `nix build --no-eval-cache -L ".#checks.$SYS.standalone-slots"` |
| `den-eval-opencode` | the de-personalized options, and the permission baseline | den | 2.2 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-opencode"` |
| `standalone-aspects` | every aspect resolves with `pkgs` alone, with no reachable `enable` | core | 2.0 | `nix build --no-eval-cache -L ".#checks.$SYS.standalone-aspects"` |
| `universal-eval-keepassxc` | the platform guard reaches the NixOS host and the user profile | core | ‡ | `nix build --no-eval-cache -L ".#checks.$SYS.universal-eval-keepassxc"` |
| `universal-eval-containers` | the Home Manager branch reads the parent through `osConfig` | core | ‡ | `nix build --no-eval-cache -L ".#checks.$SYS.universal-eval-containers"` |
| `conditional-imports-repository` | this repository's own conditional imports resolve | core | 2.0 | `nix build --no-eval-cache -L ".#checks.$SYS.conditional-imports-repository"` |
| `den-eval-ca` | the first `nixos`-only aspect, with its option in the `nixos` target | den | 1.9 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-ca"` |
| `den-smoke-host-darwin` | the same `enterTest`, from the host-derived shell | artifact | 1.7 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-smoke-host-darwin'` |
| `den-eval-coverage` | every registry aspect names a subject that evaluates | core | 1.7 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-coverage"` |
| `den-eval-priority` | a consumer's own plain definition beats the aspect's | core | 1.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-priority"` |
| `den-eval-rosetta-builder` | four option values and one launchd daemon | den | 1.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-rosetta-builder"` |
| `conditional-imports-mechanism` | the conditional-import mechanism behaves | core | 1.3 | `nix build --no-eval-cache -L ".#checks.$SYS.conditional-imports-mechanism"` |
| `den-eval-defaults` | the option default an adopter really gets | core | 1.2 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-defaults"` |
| `den-eval-guards` | both `denLib` guards fire, and the namespace holds no phantom | core | 1.2 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-guards"` |
| `den-eval-homebrew` | the aspect names no tap, no cask and no formula of its own | den | 1.1 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-homebrew"` |
| `den-artifact-host-nixos` | the NixOS toplevel holds both nix.conf lines | artifact | — | `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-artifact-host-nixos'` |
| `den-artifact-hm-host-nixos` | the NixOS host's forwarded generation writes the hooks | artifact | — | `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-artifact-hm-host-nixos'` |
| `den-artifact-home-linux` | the standalone Linux generation does the same | artifact | — | `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-artifact-home-linux'` |
| `den-smoke-devenv-linux` | the Linux shell's `enterTest` runs | artifact | — | `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-smoke-devenv-linux'` |
| `den-smoke-host-nixos` | the same, from the NixOS host's shell | artifact | — | `nix build --no-eval-cache -L '.#checks.x86_64-linux.den-smoke-host-nixos'` |

A `—` means the check needs a Linux builder, so this machine measured no time. A `‡` means the check
landed after the timing run, so it carries no measured time yet; it is an eval-only assertion set, so
it costs a few seconds. The four times over 40 s are plain builds against a warm store, so they are
lower bounds. The last five names do not exist on `aarch64-darwin`, and `aarch64-linux` carries none
of the ten per-system names. Three more entry points exist:

```bash
nix run '.#checks.aarch64-darwin.den-mvp.smoke'    # every den check, serial, PASS/FAIL per member
nix run '.#jj-experiments-run' -- -k placement -x  # a subset of the jj suite, by pytest expression
nix build '.#checks.aarch64-darwin.den-mvp.all'    # every den entity of every system
```

## When a check fails

```bash
nix build --no-eval-cache -L --keep-going ".#checks.$SYS.<name>"
```

- **`--no-eval-cache`** — Nix caches an evaluation **failure** and replays it. Measured 2026-09-11:
  `den-eval-instantiate` failed in 58 s, the next run replayed that failure in 0.6 s, and the check
  passed as soon as `--no-eval-cache` was added. A sub-second failure is almost always a stale entry.
- **`-L`** — it prints the build log. Each `den-eval-*` check writes one line per failed assertion, as
  `<name>: want <json>, got <json>`. Without `-L` you see the exit code alone.
- **`--keep-going`** — a bundle stops at its first failed member without it, so one failure hides the
  rest.

The assertions live in `den-mvp/tests.nix`, in `standalone.nix`, in `universal-guards.nix` and in
each aspect's own `enterTest`.
`bundles.nix` holds the member lists.
