---
type: Reference
description: The build-only den entities that prove the parallel den tree evaluates and builds.
timestamp: 2026-09-10T13:05:00+02:00
authored_by: agent
---

# den MVP entities

These entities exist to build. They never activate. They give the den tree a target that is
independent of any real host, so a den change is provable before it touches `hosts/`.

The task is [004-den-spike](../../docs/tasks/2026-09/generalization/004-den-spike/definition.md).
The tree itself is [modules/den/](../../modules/den/README.md).

## Layout

| Path | Kind | den output |
|---|---|---|
| `host-darwin/` | den host, class `darwin`, `aarch64-darwin` | `denConfigurations.host-darwin`, `denDevenvShells.host-darwin` |
| `host-nixos/` | den host, class `nixos`, `x86_64-linux` | `denConfigurations.host-nixos`, `denDevenvShells.host-nixos` |
| `users/` | the one den user both hosts share | `home-manager.users.dev` inside each host |
| `devenv/` | standalone shells, no den host | `denDevenvShells.devenv-darwin`, `denDevenvShells.devenv-linux` |
| `home/` | standalone home-manager, no den host | `denHomeConfigurations.home-darwin`, `denHomeConfigurations.home-linux` |

A den host produces two results: a system, and a shell from
`den.policies.host-to-devenv`. Both read one aspect list. The `devenv/` and `home/` directories
each hold every standalone entry in one file, because a standalone target needs no entity.

`modules/den/flake-module.nix` imports each directory into the den evaluation.

## Two traps the den user model sets

Both are measured, and both cost real time to find. `users/default.nix` holds the long form.

1. **`classes` defaults to `[ "user" ]`, with no `homeManager`.** den declares that default at
   `<den>/nix/lib/entities/host.nix:157`. A user that omits `homeManager` silently gets no
   home-manager generation, and the `homeManager` half of every aspect it includes goes nowhere. So
   each host states the list in full. den's own `templates/minimal` carries the comment
   `classes = [ "user" ]; # no homeManager`, which reads as if the default included it.
2. **den partitions an aspect by scope.** A four-target aspect must be included **twice** on a
   host: once in the host aspect, for `nixos`/`darwin`/`devenv`, and once in the user aspect, for
   `homeManager`. A host-scope inclusion never reaches `home-manager.users.<user>`. Measured on
   2026-09-10 with `devenv-cli`: host scope alone gave **0** devenv in
   `home-manager.users.dev.home.packages`; both scopes gave **1**.

den imports home-manager into the host by itself —
`<den>/modules/aspects/batteries/home-manager.nix` calls `den.lib.home-env.makeHomeEnv` with
`getModule = { host, ... }: inputs.home-manager."${host.class}Modules".home-manager`. So a host
needs no home-manager import of its own. It needs a user.

## Why these live here and not in `hosts/`

`hosts/` holds real machines. `flake.hostConfigurations` reads that directory one level deep and
keeps an entry that holds `default.nix` plus `meta.json` or `meta.nix`. A den entity has neither,
and a reader must not mistake it for a machine. `checks/` states the purpose in the path.

## Why no den host has `class = "devenv"`

den always includes its `insecure-predicate` aspect through `den.default.includes`. That aspect
injects `${host.class}.imports` with an OS-shaped module, and the module sets `config.nixpkgs`. A
host whose class is not an OS class then fails:

```
error: The option 'nixpkgs' does not exist. Definition values:
       - In 'devenv@insecure-predicate/os'
```

A bare `den.lib.aspects.resolve "devenv" <aspect>` never reads `den.default`, so it carries no such
limit. The standalone route uses that call and declares no entity.

Measured on 2026-09-10: the bare resolve and the same resolve from a library-only
`den.nixModule` evaluation give one identical shell drvPath
(`aw4jl6iwdyxh9flfchlnykp3cj4sbfx0`).

## Build

```bash
# current architecture only — no remote builder needed
nix build '.#checks.aarch64-darwin.den-mvp'

# every entity of every system — a foreign system needs a builder for that platform
nix build '.#checks.aarch64-darwin.den-mvp.all'
```

`nix flake check` builds the default check only. `.all` sits in `passthru`, so it stays opt-in.

## Verify without a build

```bash
nix eval --raw '.#denConfigurations' --apply 'v: toString (builtins.attrNames v)'
nix eval --raw '.#denDevenvShells'   --apply 'v: toString (builtins.attrNames v)'
nix eval --raw '.#denConfigurations.host-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.host-nixos.config.system.build.toplevel.drvPath'
```

## Pattern V1 applies here

A den evaluation reads no `self`, so no den drvPath carries this repository's tree hash. A drvPath
that does not change proves a refactor is a no-op. This holds for every den output, including the
shells — verified on 2026-09-10 by a perturbation of an unrelated tracked file.

Pattern V1 does **not** hold for the `modules/universal` route, because `flake.nix` sets
`nix-configs = self`.

## Tests

`den-mvp` builds and asserts nothing. [`tests.nix`](tests.nix) holds the assertions, in three
tiers. `checks/default.nix` merges them into `checks.<system>.*`.

| Check | Tier | What it proves |
|---|---|---|
| `den-eval-rosetta-builder` | 1 — evaluation | the aspect sets four option values and one launchd daemon |
| `den-eval-gh` | 1 — evaluation | the package, the Claude Code opt-in, and that no mutating rule entered the allowlist |
| `den-eval-guards` | 1 — evaluation | both `denLib` guards fire, the good path still returns one module, and the namespace holds the registry and no phantom |
| `den-eval-routes` | 1 — evaluation | `denLib.imports` and `denModules` give one `drvPath` in a bare nix-darwin system |
| `den-eval-devenv-cli` | 1 — evaluation | the full matrix: 12 assertions over all four den classes, both hosts, both home-manager routes and `denLib.imports` |
| `den-eval-ssh-agent` | 1 — evaluation | the user scope alone: the aspect reaches a home-manager generation and no host target |
| `den-eval-ca` | 1 — evaluation | the first `nixos`-only aspect, with the option inside the `nixos` target |
| `den-eval-zellij` | 1 — evaluation | the skill file, the two Claude Code hooks and the `kdn.isSourceRepo` switch, on both branches |
| `den-eval-opencode` | 1 — evaluation | the de-personalized options, and that a consumer's `settings` keeps the permission baseline |
| `den-eval-mcp` | 1 — evaluation | the four-aspect family: one gateway per shell, every backend name in the generated YAML |
| `den-eval-nix` | 1 — evaluation | the pre-commit hook, `den.devenv.inputs.git-hooks`, and the `$DEVENV_ROOT` expansion that replaces a frozen store path |
| `den-eval-jj` | 1 — evaluation | the coupled pair: the generated repo config, the revset and sync aliases, both git hooks, the read-only Bash allowlist, and an empty failed-assertion list in both shells |
| `den-artifact-host-darwin` | 2 — artifact | the built toplevel holds three `nix.conf` lines, `sw/bin/devenv`, the launchd plist and the `activate` reference |
| `den-artifact-hm-host-darwin` | 2 — artifact | the generation den forwards to `home-manager.users.dev` writes all three shell hooks |
| `den-artifact-home-darwin` | 2 — artifact | the same, for the **standalone** home-manager route that carries no den entity |
| `den-artifact-host-nixos` | 2 — artifact | the NixOS toplevel holds both `nix.conf` lines and `sw/bin/devenv` |
| `den-artifact-hm-host-nixos` | 2 — artifact | the NixOS host's forwarded generation writes all three shell hooks |
| `den-artifact-home-linux` | 2 — artifact | the standalone Linux home-manager generation does the same |
| `den-smoke-devenv-darwin` | 3 — smoke run | `gh` and `devenv` really run, from the standalone shell's own `enterTest` |
| `den-smoke-host-darwin` | 3 — smoke run | the same, from the shell that `den.policies.host-to-devenv` derives |
| `den-smoke-devenv-linux` | 3 — smoke run | the same, on `x86_64-linux` |
| `den-smoke-host-nixos` | 3 — smoke run | the same, from the NixOS host's shell |

Tier 1 runs on any machine: the comparison is an evaluation and the derivation is local. Tier 2 and
tier 3 build a real artifact, so `tests.nix` keeps only this machine's entries — the same rule the
`den-mvp` aggregate follows.

**25 of 25 pass on an `aarch64-darwin` machine**, measured on 2026-09-11: 20 evaluation, 3 artifact
and 2 smoke. The 20 evaluation checks assert about 216 values together, and `den-eval-jj` holds 32
of them. The five `x86_64-linux` entries evaluate to a `drvPath` from Darwin, and they need a Linux
builder to build. `nix eval '.#checks.<system>'` lists one name more than that on each system,
because the `den-mvp` build gate joins the set.

The registry at [`modules/den/lib.nix`](../../modules/den/lib.nix) holds **20** aspects. Four checks
are cross-cutting. Each one reads a **bare consumer** — a plain evaluation with no den entity, no
`kdnConfig` and no overlay, one helper per class:

| Check | What it proves |
|---|---|
| `den-eval-defaults` | the option default an adopter really gets: the opt-in boundary, and every de-personalized value |
| `den-eval-priority` | a consumer's own plain definition beats the aspect's, and the one place where it still cannot |
| `den-eval-frozen-paths` | no backend freezes an environment value, and the gateway finds its configuration at run time |
| `den-eval-coverage` | every registry aspect names a subject that evaluates its target module |

**No tier activates anything.** Tier 2 reads a built store path and never executes it. Tier 3 runs
devenv's `config.test`, which devenv keeps separate from `enterShell`, so no assertion runs on
shell entry either. Nothing here needs sudo.

Tier 2 is nix-darwin's own pattern. `<nix-darwin>/release.nix:15-57` wraps a test module in a
`runCommand` that greps `${config.out}/activate`; `<nix-darwin>/tests/launchd-daemons.nix` is the
model.

### An aspect owns its own smoke test

The assertions live in the aspect, as devenv's `enterTest` option — see
[`modules/den/aspects/gh.nix`](../../modules/den/aspects/gh.nix). So they travel with the aspect to
an external adopter, and `devenv test` runs them too. Keep every assertion offline: the check runs
in a build sandbox with no network and no real home.

### Semi-automated: one command, one summary

```bash
nix run '.#checks.aarch64-darwin.den-mvp.smoke'
```

It builds every check above plus the `den-mvp` aggregate, one at a time, and prints a PASS/FAIL
summary. Pass a flake reference as the first argument to test another checkout.

### Not covered yet

- **A VM test.** `pkgs.testers.runNixOSTest` is the right tool for `host-nixos`. The host **does**
  carry a real `nixos`-class aspect now, so a booted guest is no longer vacuous. But every value it
  would read is a static option value or a file in the toplevel, and tier 1 and tier 2 read both. A
  VM earns its cost only for a runtime behaviour — a service that must start, an activation that
  must converge. No darwin VM framework exists at all.
- **A slot-against-den parity check.** `hosts/anji` versus `denConfigurations.host-darwin` agrees
  today, measured by hand on 2026-09-10. It is not automated, because it evaluates a whole personal
  host — about 93 s, and it reads sops metadata.
