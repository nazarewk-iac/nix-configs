---
type: Task
description: Explore partial augmentation of a universal (old-tree) host with one den aspect through denLib.imports, so a host adopts one aspect at a time and migrates gradually.
status: done
solution: done.md
parent: ../definition.md
authored_by: agent
timestamp: 2026-09-25T17:29:39+02:00
---

# 000 — universal augmentation

Parent task: [../definition.md](../definition.md). Design: [../design.md](../design.md).

## Context

A universal host is a host under `hosts/` that imports `modules/universal`. Four hosts consume the
zellij web certificate: oams, brys, etra and moss. Sub-task
[006 — zellij migration](../006-zellij-migration/definition.md) changes those four hosts.

Those four hosts stay on the universal tree. Decision D2 keeps them there. So the certificate tree
must reach a universal host without a full den migration. This sub-task verifies that route.

The route is the den library. `modules/den/lib.nix` exports `denLib.imports`. It returns plain
modules. A universal host imports them with no den adoption.

## The mechanism

`denLib.imports` takes a class and an aspect list. It returns a list of already-resolved plain
modules. The caller drops the list into its own `imports`.

```nix
denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }
```

The function resolves each name through `den.ful.kdn` and returns one module per name
(`modules/den/lib.nix:474-500`). It uses `den.nixModule`, not `den.flakeModule`
(`modules/den/lib.nix:10-13`). So the caller loads no den entity machinery: no `den.hosts`, no
`den.schema`, no `den.default`.

The class names an evaluation domain. A universal NixOS host passes `class = "nixos"`. The
`certificates` aspect emits the `nixos` class among others.

## The exact line

The host `hosts/oams/default.nix` holds this import block at `hosts/oams/default.nix:31-35`:

```nix
imports = [
  kdnConfig.self.nixosModules.default
  slots.config.nixos
];
```

Add one line:

```nix
{ imports = kdnConfig.self.denLib.imports { class = "nixos"; aspects = [ "certificates" ]; }; }
```

`kdnConfig.self` is the flake. `flake.denLib` is the library handle
(`modules/den/flake-module.nix:181`).

The wrapper `{ imports = …; }` is mandatory. `denLib.imports` returns a list. A bare list inside an
`imports` list fails with `error: Module imports can't be nested lists.` (measured in
[docs/den-for-adopters.md](../../../../den-for-adopters.md) § "The two entry points").

The same line works for brys, etra and moss. Each host has its own import block.

Until sub-task 002 lands the `certificates` aspect, the same line proves the mechanism with an
existing aspect, for example `aspects = [ "gh" ]` on the `devenv` class. The mechanism is not
certificate-specific.

## Caveats

### Option-declaration clash

The module system merges two declarations of one option only when their types match. A type
mismatch fails at evaluation:

```
error: The option `foo' in `<unknown-file>' is already declared in `<unknown-file>'.
```

Measured on 2026-09-25 with a two-module `lib.evalModules`. Two `str` declarations merged and
returned one value. A `str` declaration and an `int` declaration threw the error above.

One option is declared in both trees today: `kdn.hostName`.

- `modules/universal/_options.nix:16` declares it as `str`, with no default.
- `modules/den/common/host-name.nix:34` declares it as `str`, with a default.

Both are `str`, so the two declarations merge. An aspect that declares a `kdn.*` option the
universal tree already declares with a different type fails. Check the type before the import.

A value clash is separate. Two plain assignments to one option at the same priority do not resolve.
The universal tree writes `kdn.hostName = cfg.hostName` at `modules/universal/default.nix:104`. The
den declaration writes no value, only a default. So the two do not collide. See
[docs/den-for-adopters.md](../../../../den-for-adopters.md) § "How to override a value".

### `den.default` is absent on the library route

`den.default` does not exist on `denLib`. `den.nixModule` loads four files and exposes only
`{ aspects, lib, policies }` (`modules/den/lib.nix:10-13`). So no global switch can reach a
universal host, and the design does not use one anyway (decision D3).

This sub-task therefore names every aspect in the host's own `imports` line. That is the explicit
per-entity include of decision D3. The library route forces it: no global switch exists.

### `standalone-aspects`

`checks/standalone.nix` gates every file under `modules/den/aspects/`. Each aspect must pass these
rules:

- No reachable `enable` option. Inclusion is the switch.
- No `kdnConfig`, no `modules/universal` and no `modules/meta`.
- Targets take `pkgs` only.

The augmentation line adds no exception. The imported aspect carries the same rules into the
universal host. A universal host may read `kdnConfig`; the aspect may not.

### Evaluation cost

`denLib.imports` starts a fresh den library evaluation on every call. The `eval` call sits inside
the function at `modules/den/lib.nix:483`. One call costs about one second
(`modules/den/lib.nix:400`).

A universal host that adds the line pays that cost once at evaluation time. `denLib.pairModules`
shares one `defaultDen` (`modules/den/lib.nix:423`), but it returns one module and not a list, so it
does not fit the `imports = [ … ]` shape. The eval-performance task tracks the lever:
[docs/tasks/2026-09/eval-performance/design.md](../../eval-performance/design.md) § 3.

## Why this is first

Sub-task 006 targets the four universal hosts. It needs the augmentation line to reach them. So
000 must land before 006, or 006 must wait.

Sub-task 004 (the CLI walk) also reads the universal tree. It reads
`nixosConfigurations.<host>.config.kdn.certificates`. The augmentation line makes that option exist
on a universal host.

## Acceptance

- A universal host evaluates with one den aspect in its `imports` list. Command:
  `nix eval --no-eval-cache .#nixosConfigurations.oams.config.system.build.toplevel.drvPath`.
- The option set is readable:
  `nix eval --no-eval-cache --json .#nixosConfigurations.oams.config.kdn.certificates`.
- No duplicate option declaration. The evaluation raises no "already declared" error.
- `checks/standalone.nix` still passes for the imported aspect.

## Out of scope

- The `certificates` aspect itself. See [002 — cert declarations](../002-cert-declarations/definition.md).
- The CLI walk. See [004 — cert CLI](../004-cert-cli/definition.md).
- The zellij migration. See [006 — zellij migration](../006-zellij-migration/definition.md).
- The den flake route. See [design.md](../design.md) § 2.
