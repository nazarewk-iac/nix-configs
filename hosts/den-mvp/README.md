---
type: Reference
description: Build-only den hosts that mirror the real hosts, so a den module can be compared against the equivalent slot.
timestamp: 2026-09-10T09:10:00+02:00
authored_by: agent
---

# den MVP hosts

Two hosts live here. Each one is **build-only**. Each one exists to answer one question:

> Does the den module produce the same configuration as the slot it replaces?

| Host | Class | System | Mirrors | Compare against |
|---|---|---|---|---|
| [den-darwin](den-darwin/default.nix) | `darwin` | `aarch64-darwin` | a real Darwin workstation | `darwinConfigurations.anji` |
| [den-nixos](den-nixos/default.nix) | `nixos` | `x86_64-linux` | a real NixOS workstation | `nixosConfigurations.brys` |

Neither host activates. Neither holds personal data. No machine uses either name.

## Why this directory is invisible to the host loader

`flake.hostConfigurations` (`flake.nix:264`) calls `builtins.readDir ./hosts` and reads **one level
only**. It keeps an entry when the entry holds a `default.nix` **and** a `meta.json` or a
`meta.nix`. `hosts/den-mvp/` holds none of the three, so `filterAttrs` drops it and the two hosts
below stay invisible to that loader.

That invisibility is the point. Every entry the loader keeps goes through `modules/meta`, and den
exists to replace that pre-pass. A den host that inherits `modules/meta` proves nothing.
`hosts/install-iso/` is the existing precedent for a directory under `hosts/` that the loader skips.

**Do not add a `meta.json`, a `meta.nix` or a `default.nix` to `hosts/den-mvp/` itself.** Either of
the first two, together with a `default.nix`, would pull this directory into the normal host set.

## Who reads these files

`modules/den/flake-module.nix` imports both directories into den's own `lib.evalModules`. The
results appear as:

```
flake.denConfigurations.den-darwin       a nix-darwin system
flake.denConfigurations.den-nixos        a NixOS system
flake.denDevenvShells.den-darwin         a devenv shell
flake.denDevenvShells.den-nixos          a devenv shell
```

## Build them

```bash
# evaluate (fast, no build)
nix eval --raw '.#denConfigurations.den-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.den-nixos.config.system.build.toplevel.drvPath'

# build — den-darwin needs a Darwin machine; den-nixos needs a Linux builder
nix build --no-link '.#denConfigurations.den-darwin.config.system.build.toplevel'
nix build --no-link '.#denConfigurations.den-nixos.config.system.build.toplevel'
```

## Compare a den module against its slot

Compare **option values**, never derivation paths. `flake.nix:250` sets `nix-configs = self`, so the
whole tree hash enters every derivation and two different hosts can never match on a `drvPath`.

```bash
# the slot route                                    the den route
nix eval --json '.#darwinConfigurations.anji.config.nix-rosetta-builder'
nix eval --json '.#denConfigurations.den-darwin.config.nix-rosetta-builder'
```

A useful diff of one option subtree:

```bash
diff <(nix eval --json '.#darwinConfigurations.anji.config.nix-rosetta-builder' | jq -S .) \
     <(nix eval --json '.#denConfigurations.den-darwin.config.nix-rosetta-builder' | jq -S .)
```

### Result on 2026-09-10 — `anji` against `den-darwin`

| Option subtree | Verdict |
|---|---|
| `config.nix-rosetta-builder` | **identical** |
| `config.nix.settings.builders-use-substitutes` | **identical** |
| `config.nix.buildMachines` | differs, for a known reason |

`nix.buildMachines` differs because `anji` also gets personal remote builders from
`modules/universal/profile/remote-builders/`. den ports none of that tree, so the difference is
expected and it is not a defect. Read `nix.buildMachines` for the Rosetta entry only.

## Pattern V1 works for a den host

The hub records that Pattern V1 — the `drvPath` equality gate — is unusable for the slot route:
`flake.nix:250` sets `nix-configs = self`, so any new file changes the tree hash and every
derivation path with it.

**A den configuration is immune.** den's evaluation never reads `self`. Measured on 2026-09-10:
`denConfigurations.den-darwin` kept the byte-identical `drvPath`
`7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move **and** the
addition of `den-nixos`.

So use Pattern V1 as a real no-op gate for every den refactor:

```bash
nix eval --raw '.#denConfigurations.den-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.den-nixos.config.system.build.toplevel.drvPath'
```

Only `kdn.den.devenv.root` reads `self`, and that value reaches the devenv shells alone. So a
`denDevenvShells` path does change with the tree hash. Gate on `denConfigurations`, not on
`denDevenvShells`.

## The limit of the mimicry

These hosts mirror the **slot** surface only. They do not mirror `modules/universal`, and they
cannot: den holds no port of that tree yet. So a diff of two whole systems is meaningless today.
Diff one option subtree that a ported aspect owns, and nothing else.

Today exactly one aspect is ported (`rosetta-builder`, core options only), so `den-nixos` carries no
aspect at all. It is the landing place for the first ported NixOS aspect.
