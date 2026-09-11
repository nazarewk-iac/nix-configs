---
type: Reference
title: Checks — bundles and standalone commands
description: Every check, its bundle, its measured time and its exact standalone command.
authored_by: agent
timestamp: 2026-09-11T20:45:00+02:00
---

# Checks

**Do not run a bare `nix flake check`.** It builds all **63** attributes of `checks.<system>` on
`aarch64-darwin`, counted 2026-09-11 with:

```bash
nix eval --raw '.#checks.aarch64-darwin' --apply 'x: toString (builtins.length (builtins.attrNames x))'
```

Six of the 63 are the bundles, so 57 are real checks. The bare run measured **660.6 s** before the 30
`dev-*` aspects landed. `den-eval-instantiate` then grew by 300 s, and 12 more checks landed after
that run. So **960 s is a lower bound, not a measurement**. Nobody re-measures it: the measurement
costs the same 15 minutes the rule exists to save. `bundle-slow` alone runs 710.6 s on a warm store.
Four checks cost over a minute each: `den-eval-instantiate` runs 358 s and `jj-experiments-pytest`
runs 188 s. Run a bundle instead.

## Bundles

One command per bundle; nix builds the members in parallel. Swap `aarch64-darwin` for `x86_64-linux` or
`aarch64-linux` on those systems.

```bash
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-core'      # 11.1 s, after any edit
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-den'       # 108.0 s, modules/den/aspects/
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-pkgs'      # 18.0 s, packages/
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-artifact'  # 43.7 s, a built artifact
nix build --no-eval-cache -L '.#checks.aarch64-darwin.bundle-slow'      # 710.6 s, before a hand-off
```

`bundle-core` is the broad tripwire: the plumbing, the standalone rule and the cross-cutting set. Run it
first. `bundle-den` holds one assertion set per den aspect. Two members are the exception: `den-eval-hw`
sits in `bundle-slow` at 25.3 s and `den-eval-programs` at 19.4 s, both under the 60 s mark. Each one
was the heaviest member of `bundle-den` when it moved. Four batches of aspects took `bundle-den` to
75.4 s and the first shed brought it to about 50 s. Five more area checks then took it to 98.6 s, and
the second shed brought it to 79.1 s. Five more `den-eval-*` checks then landed, and the bundle now
runs **108.0 s**, measured 2026-09-11.

### The 60 s ceiling now has a third exception: `bundle-den`

`bundle-den` keeps its time. It sheds no further member. The reasoning, recorded 2026-09-11:

- A shed moves cost into `bundle-slow`, and nobody runs that bundle per edit. So a shed **hides** the
  cost. It does not remove it.
- `bundle-core`, at 11.1 s, is the real per-edit tripwire. `bundle-den` is the area bundle you run when
  you touch an aspect, and about 100 s is acceptable for that job.
- 205 aspects cannot fit one 60 s bundle. A split needs a new bundle name, and a bundle name is an
  infrastructure decision that belongs to the repository owner.

Nothing above closes the question. **The owner should revise this decision.** The alternative is a
split of `bundle-den` into two area bundles. The five newest members are all cheap — `den-eval-user`
10.6 s, `den-eval-batch2` 9.3 s, `den-eval-router` 5.8 s, `den-eval-harness-split` 1.8 s and
`den-eval-graphical` 1.7 s — so no single shed helps.

`bundle-slow` and `bundle-vm` are the other two declared exceptions, and `bundle-vm` is reserved and
empty because no VM test exists yet. `bundle-artifact` holds the 43.7 s only with the system closure
already in the store, and it is empty on `aarch64-linux`, which carries no `den-artifact-*` and no
`den-smoke-*`.

## Every check

Measured 2026-09-11 on `aarch64-darwin`, warm store, one check per invocation. Slowest first. Set `SYS`
first: `SYS=aarch64-darwin` — or `x86_64-linux`, or `aarch64-linux`.

**Every time below is a snapshot of 2026-09-11.** A time drifts up as its area grows: an assertion set
gets more subjects with each batch of aspects. Nobody re-measures the whole table per edit, because one
run of all 57 checks costs more than 15 minutes. Re-measure the one row you change, and the bundle it
joins.

| Check | Proves | Bundle | Sec | Standalone command |
|---|---|---|---|---|
| `den-eval-instantiate` | every (aspect, class) pair forces its target module body | slow | 358.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-instantiate"` |
| `jj-experiments-pytest` | the isolated 3-repo jj suite, headless | slow | 188.4 | `nix build --no-eval-cache -L ".#checks.$SYS.jj-experiments-pytest"` |
| `den-eval-routes` | `denLib.imports` and `denModules` give one `drvPath` | slow | 83.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-routes"` |
| `den-mvp` | the whole parallel den tree evaluates and builds | slow | 75.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-mvp"` |
| `den-artifact-host-darwin` | the darwin toplevel holds the nix.conf lines and the plist | artifact | 46.7 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-artifact-host-darwin'` |
| `den-eval-services` | 48 assertions over 7 bare consumers: the service, managed-file and virtualisation aspects | den | 31.8 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-services"` |
| `den-eval-hw` | 36 assertions over 7 bare consumers: the 17 hardware aspects | slow | 23.6 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-hw"` |
| `den-eval-programs` | 56 assertions over 6 bare consumers: the 40 `program-*` aspects | slow | 19.4 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-programs"` |
| `den-smoke-devenv-darwin` | the shell's own `enterTest` really runs | artifact | 18.9 | `nix build --no-eval-cache -L '.#checks.aarch64-darwin.den-smoke-devenv-darwin'` |
| `zellij-llm-pytest` | the `zellij-llm` package's own pytest suite | pkgs | 17.1 | `nix build --no-eval-cache -L ".#checks.$SYS.zellij-llm-pytest"` |
| `den-eval-toolset-small` | 14 assertions: the toolset, packaging, emulation, outputs and monitoring aspects | den | 14.7 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-toolset-small"` |
| `den-eval-networking` | 27 assertions over 4 bare consumers: the seven `net-*` aspects | den | 13.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-networking"` |
| `den-eval-k8s` | 24 assertions over 9 bare consumers: the five `service-k8s*` aspects | den | 12.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-k8s"` |
| `den-eval-machine-profiles` | 19 assertions over 6 bare consumers: the 13 machine-profile bundles, plus the `includes` graph of every one | den | 12.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-machine-profiles"` |
| `den-eval-development` | 26 assertions over 22 bare consumers: the 30 `dev-*` aspects | den | 11.2 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-development"` |
| `den-eval-security` | 22 assertions over 7 bare consumers: the four `security-*` aspects | den | 11.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-security"` |
| `den-eval-virtualisation` | 11 assertions over 3 bare consumers: the two `virt-microvm-*` aspects | den | 11.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-virtualisation"` |
| `den-eval-user` | 23 assertions over 3 bare consumers: the `user` aspect and the shared `kdn.users` schema | den | 10.6 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-user"` |
| `den-eval-batch2` | 12 assertions over 3 bare consumers: the `apps`, `locale` and `secrets` aspects, plus both design traps | den | 9.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-batch2"` |
| `den-eval-desktop-leaves` | 35 assertions over 7 bare consumers: the 11 desktop leaf aspects | den | 9.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-desktop-leaves"` |
| `den-eval-root-orphans` | 12 assertions over 4 bare consumers: `stylix`, `stylix-home` and `hm-bootstrap` | den | 8.9 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-root-orphans"` |
| `den-eval-disks-fs` | 22 assertions over 9 bare consumers: the disks and filesystem aspects | den | 7.3 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-disks-fs"` |
| `den-eval-sway-core` | 26 assertions over 5 bare consumers: the sway session core and its VNC extras | den | 7.0 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-sway-core"` |
| `den-eval-router` | 22 assertions over 5 bare consumers: the five `net-router*` aspects, with RFC placeholder data only | den | 5.8 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-router"` |
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
| `den-eval-harness-split` | the directory scan of `den-mvp/assertions/` finds a file, and every `harness.nix` export arrives | den | 1.8 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-harness-split"` |
| `den-eval-graphical` | the shared `kdn.graphical` switch, in both end states | den | 1.7 | `nix build --no-eval-cache -L ".#checks.$SYS.den-eval-graphical"` |
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
