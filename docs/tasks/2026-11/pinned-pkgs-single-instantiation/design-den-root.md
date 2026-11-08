---
type: Design
description: Research, design options, plan, and hostile review for one pinned pkgs per (system, variant), produced by an isolated den root and forced into every target.
status: draft
task: definition.md
authored_by: agent
timestamp: 2026-11-08T20:25:55+01:00
---

# One pinned `pkgs` per (system, variant) — den root design

This document answers [definition.md](definition.md). It has five parts: (A) research, (B) three
design options with a recommendation, (C) the plan for the recommended option, (D) a hostile
review, and (E) success metrics and verification.

**Scope rule.** This file is a design. It changes no source file. Every `file:line` reference is to
the tree at the time of writing.

---

## A. Research findings

### A.1 Where nixpkgs is instantiated today

`nix` does not memoise `import inputs.nixpkgs { … }`. Each call builds a new top-level package set.
The sites that matter for a host evaluation are:

| # | Site | What it does today | How to collapse it |
| --- | --- | --- | --- |
| 1 | `flake.nix:466` | `meta.nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; overlays = [ self.overlays.default ]; }` — colmena's own CLI pkgs. | One shared value `self.pkgs."x86_64-linux"."default"`. |
| 2 | `flake.nix:481-484` | `meta.nodeNixpkgs."<host>"` — **one full import per host** inside one colmena evaluation. | One shared value per system; many nodes then share one thunk. |
| 3 | `flake.nix:511` | `pkgs = inputs.nixpkgs.legacyPackages.${system}.extend self.overlays.default` — easykubenix. | `self.pkgs.${system}.default`. |
| 4 | `flake.nix:526` | `_module.args.pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.default` — perSystem (`checks`, `packages`, apps). | `self.pkgs.${system}.default`. |
| 5 | `flake.nix:429-439` | `lib.nixosSystem` with no `nixpkgs.pkgs`; nixpkgs builds its own set through `defaultPkgs` (`nixpkgs/modules/misc/nixpkgs.nix:76`). | Set `nixpkgs.pkgs` in a module. |
| 6 | `flake.nix:447-459` | `lib.darwinSystem` plus `{ nixpkgs.system = host.system; }` at `flake.nix:451`; nix-darwin builds its own set through `defaultPkgs` (`nix-darwin/modules/nix/nixpkgs.nix:76`). | Set `nixpkgs.pkgs`; delete the `nixpkgs.system` line. |
| 7 | `modules/universal/default.nix:96` | `home-manager.useGlobalPkgs = false`; each HM user imports nixpkgs again (via `_hm-bootstrap.nix`). | `useGlobalPkgs = true`; HM then uses the host `pkgs` (`home-manager/nixos/common.nix:45`). |
| 8 | `modules/den/classes/devenv.nix:48` | `_module.args.pkgs = import inputs.nixpkgs { inherit system; }` inside every devenv evaluation. | `_module.args.pkgs = self.pkgs.${system}.default`. |
| 9 | `modules/universal/default.nix:136` | `nixpkgs.overlays = [ self.overlays.default ]` for every host; a **second** overlay application on top of the instance. | Guard it off for a pinned host (the overlay is already baked). |
| 10 | `modules/universal/default.nix:167-190` | A second `nixpkgs.overlays` list (Python metadata and ceph fixes). Static, no host data. | Move these two overlays into the shared variant (see A.4). |

Out of scope, and must be recorded as such:

- `hosts/anji/default.nix:434` runs a nested `import (nixpkgsPath + "/nixos")` for
  `nix.linux-builder`. That is a guest image, not the host target.
- `hosts-den/pryll/default.nix:29` builds `hostPkgs` for the den test host.
- `checks/den-mvp/assertions/*.nix`, `checks/den-mvp/harness.nix:118,146`,
  `checks/den-mvp/home/default.nix:77`, `checks/jj-experiments/subset-runner.nix:22` and
  `checks/universal-guards.nix:61` import nixpkgs in the check tree. Route them through
  `self.pkgs` where cheap; a check may keep a local import and be documented.
- `modules/den/aspects/fs.nix:308` and `modules/den/aspects/disks.nix:69` import
  `nixpkgs/nixos/lib/utils.nix`. That is a library file, not a package-set instantiation. No change.

### A.2 den internals needed to add a new class/target

`inputs.den` exposes (from `<den>/nix/default.nix`):

| Export | Shape | Use for us |
| --- | --- | --- |
| `flakeModule` | loads all of den's `modules/` tree (the "batteries"). | Not needed. Heavy. |
| `nixModule inputs` | imports four files (`lib.nix`, `policies.nix`, `aspects.nix`, `pipes.nix`); exposes `{ aspects, lib, policies }` only. | This is the library route. |
| `namespace name export` | creates `den.ful.<name>`, a module-argument alias, and (if `export`) `flake.denful.<name>` (`<den>/nix/lib/namespace.nix`). | Use with `export = false`. |
| `flakeOutputs.<name>` | one option declaration per flake output name (`<den>/nix/flakeOutputs.nix`). | Needed only if we want `config.flake.*` from den entities. |
| `lib` | the raw den library (`<den>/nix/lib/default.nix`). | `den.lib.aspects.resolve`, `den.lib.policy.*`. |

How `modules/den/classes/devenv.nix` adds a class:

1. Declare the class: `den.classes.devenv = { };` (`modules/den/classes/devenv.nix:151`). den's
   `den.classes` option is `lazyAttrsOf classSchemaType` (`<den>/modules/options.nix:125-129`).
2. Declare the flake output the class writes to: `options.flake.devenvShells = …`
   (`modules/den/classes/devenv.nix:86-90`). den declares one option per known output name only;
   a new output needs its own declaration (`<den>/nix/flakeOutputs.nix`).
3. Declare a policy that instantiates the class into that output:
   `den.lib.policy.instantiate { name; class; instantiate; intoAttr; }`
   (`modules/den/classes/devenv.nix:156-174`).

How aspects resolve per class: `den.lib.aspects.resolve "<class>" <aspect>` reads the aspect's
`<class>` key. An aspect file writes `kdn.<name>.<class> = { config, lib, pkgs, ... }: …;`
(`modules/den/aspects/gh.nix:15-17`). At the top level of an aspect file `kdn` is the namespace
alias; `mkAliasOptionModule [ "kdn" ] [ "den" "ful" "kdn" ]` makes it so
(`<den>/nix/lib/namespace.nix:26`). The registry in `modules/den/lib.nix:36-253` maps an aspect
name to its file, and `pairClasses` reads the class keys off the aspect itself
(`modules/den/lib.nix:382-401`).

**Feasibility of a second, isolated `evalModules` root.** Yes. Two shapes work:

- **Library route (recommended).** `lib.evalModules { specialArgs.inputs = …; modules = [
  (inputs.den.nixModule denInputs) (inputs.den.namespace "pkgsroot" false) ./classes/pkgs.nix
  …variant modules… ]; }` — the same shape as `modules/den/lib.nix:291-310`. It loads no batteries,
  no `den.hosts`, no `den.schema`. Cost is the den library evaluation plus the nixpkgs instantiations
  we ask for.
- **`flakeModule` route.** Loads every den module and the entity machinery. It brings `den.hosts`,
  policies and the output pipeline. It is more code and more eval for a target that produces one
  value per system. Reject it.

Trade-off versus extending the existing tree: a second root pays a second den library evaluation.
An extension pays none, but it puts a `pkgs` concern into `den.ful.kdn`, and the exported namespace
is the adopter surface (`modules/den/flake-module.nix:99-248`). A phantom aspect there would leak to
`flake.denful.kdn` (see the `classes/devenv.nix:81-85` warning about the earlier phantom `den`
aspect). Isolation is the safer shape.

### A.3 `nixpkgs.pkgs` across the targets

The task text says `nixpkgs.pkgs` is "mutually exclusive with overlays/config". That is only half
true on the pinned revisions. Verified from source:

| Target | `nixpkgs.pkgs` supported | `overlays` with `pkgs` | `config` with `pkgs` | `hostPlatform`/`system` with `pkgs` |
| --- | --- | --- | --- | --- |
| NixOS 26.11 | Yes (`nixpkgs/modules/misc/nixpkgs.nix:107`). | **Appended** after the baked ones: `cfg.pkgs.appendOverlays cfg.overlays` (`:107`). | **Assertion failure** if not `{ }` (`:409-418`). | Ignored (`:173,213,245,277,303,347`). |
| nix-darwin `4cff07de` | Yes (`modules/nix/nixpkgs.nix:103`). | **Appended** (`:103`). | **Assertion failure** if not `{ }` (`:319-329`). | Ignored (`:170-199`). |

> The nixpkgs internal line numbers come from the 26.11 tree in the local store; the option names
> are stable, but the lines may move by a few across revisions. The nix-darwin lines are from the
> pinned rev `4cff07de`.

So the real constraints are:

1. `nixpkgs.config` must be exactly `{ }` on a pinned host. It is **not** mutually exclusive with
   `overlays`. Overlays are appended, and that is precisely the danger: a stale per-module overlay
   will silently double-apply with no error (see D).
2. The `nixpkgs.pkgs` system must match the host. The system-match assertion only runs when the
   host built the set itself (`constructedByMe`, nixpkgs `:64,368-406`; nix-darwin `:285-311`),
   so with an external `pkgs` a mismatch is **not** asserted. Add our own assertion.
3. `nixpkgs.system = host.system` at `flake.nix:451` becomes a no-op for a pinned darwin host and
   should be removed with the `mkIf`.

Home Manager: `useGlobalPkgs = true` makes HM use the system `pkgs` and disables HM
`nixpkgs.*` options (`home-manager/nixos/common.nix:45,95-101`). The repo currently sets
`useGlobalPkgs = false` (`modules/universal/default.nix:96`) and bridges `nixpkgs.config`/overlays
into each user through `modules/universal/_hm-bootstrap.nix:26-44`. A pinned host needs
`useGlobalPkgs = true` and must drop that bridge.

devenv: the top-level module takes `pkgs` as a module argument (`<devenv>/src/modules/top-level.nix:1-6`).
`classes/devenv.nix:48` supplies it with a fresh import. Replace that one line. `devenv.overlays`
(`top-level.nix:102-115`) is a separate list; keep it empty for a pinned shell. The devenv **CLI**
route (`devenv.nix` at the repo root) builds its own pkgs before any of this runs. We cannot force
that from the flake. This is an open question (A.5).

Colmena: `meta.nixpkgs` and `meta.nodeNixpkgs.<host>` both accept a package set
(`flake.nix:466,481`). Replace both with the shared value. Do not keep a per-host import.

easykubenix (`flake.nix:511`) and perSystem (`flake.nix:526`) both take a package set directly.

**nix-darwin acceptance: verified.** `nix-darwin/modules/nix/nixpkgs.nix` at rev `4cff07de` declares
`options.nixpkgs.pkgs` (`:109-132`) and uses `cfg.pkgs.appendOverlays cfg.overlays` (`:103`). The
`config` assertion is at `:319-329`. No empirical evaluation was run (a `nix eval` of the nix-darwin
input exceeded the time box). The source is unambiguous, so treat this as source-verified, not
machine-verified.

**HM `useGlobalPkgs` weight: unmeasured.** The `eval-performance` research records it as a lever but
also as unmeasured (`docs/tasks/2026-09/eval-performance/research.md:817,853-854`). Treat a HM
speed-up as a hypothesis until measured.

### A.4 The host-specific overlays: which are truly host-dependent

The six overlay sites in the task, classified by whether the overlay body reads host `config`:

| Overlay | File:line | Reads host config? | Verdict |
| --- | --- | --- | --- |
| sops `jsonTemplate` | old `modules/universal/security/secrets/sops/default.nix:185-217`; den `modules/den/aspects/security-secrets-sops.nix:285-307,329,388` | **No.** Uses `final.formats.json` and `prev.writeText` only. | **Bake into `default`.** |
| keepass plugin set | old `modules/universal/programs/keepass/default.nix:19-29`; den `modules/den/aspects/program-keepass.nix:8-18` | **No.** Static plugin names. | **Bake into `default`.** |
| openvpn3 patch | old `modules/universal/networking/openvpn/default.nix:200-209`; den `modules/den/aspects/net-openvpn.nix:324-334` | **No.** Static patch path. | **Bake into `default`.** |
| net-router `jsonTemplate` | old `modules/universal/networking/router/default.nix` reads `pkgs.jsonTemplate` (e.g. `:533,1052`); den `modules/den/aspects/net-router/json-template.nix` carries its own copy | **No.** | **Bake the helper into `default`** (or let the den aspect keep its local copy). |
| age `sops` wrapper | old `modules/universal/security/secrets/age/default.nix:221-227`; den `modules/den/aspects/security-secrets-age.nix:319-325` | **Yes.** `mkSopsWrapper` closes over `cfg.plugins`/`cfg.genScripts` (old `:14-46`; den `:270-307`). | **Cannot bake.** Refactor (see below). |
| hw-gpu `supergfxctl` | old `modules/universal/hw/gpu/default.nix:54-63`; den `modules/den/aspects/hw-gpu.nix:144-146` | **Only when** `multiGPU.package != null`; the value is consumer-supplied. | **Per-host variant or refactor.** |

The age wrapper is the one genuine blocker. It wraps the `sops` CLI with the host's age plugins and
key generators. The wrapper is installed through the overlay only so `pkgs.sops` becomes the wrapper.
Three facts reduce the risk:

- `sops-nix` templates use `sops-install-secrets`, not the `sops` CLI
  (`sops-nix/modules/sops/templates/default.nix`), and `sops.package` is the
  `sops-install-secrets` package (`sops-nix/modules/sops/default.nix:274-279`).
- Two modules install `pkgs.sops` into the system package list (`modules/universal/security/secrets/sops/default.nix:245`
  and `modules/den/aspects/security-secrets-sops.nix:280`). These are the only readers.
- Both can point at a plain wrapper package expression instead of `pkgs.sops`.

So the wrapper can move from an overlay to `environment.systemPackages` with `lib.hiPrio`, and those
two lines can be changed to use the wrapper expression, without a second full nixpkgs for the whole
system. This is the recommended fix; it removes the blocker instead of accepting a second
instantiation. The change touches two files and is worth it: a second instantiation per host is the
cost the task exists to remove.

The `hw-gpu` case affects only laptops with two GPUs (the task names the pinned 5.2.1 build). Keep
it as a documented per-host variant or move `services.supergfxd`'s package binding to a small
`pkgs.extend` on that one host. It is not a fleet-wide requirement.

`nixpkgs.config` uniformity: the shared config is `{ allowAliases = true; allowUnfree = true;
permittedInsecurePackages = [ … ]; }` (`modules/universal/nix.nix:58-65`,
`modules/universal/_options.nix:41-70`). No host overrides `allowUnfree`. The only divergent line is
`nixpkgs.config.allowUnfreePredicate` in `modules/universal/profile/machine/gaming/default.nix:33`.
Two hosts enable gaming: `hosts/brys/default.nix` and `hosts/oams/default.nix`, both `x86_64-linux`.
With `allowUnfree = true` the predicate grants nothing new, and the den port already drops it
(`modules/den/aspects/profile-gaming.nix:24-27`). So **one config per system is achievable**: unify
to the shared set and drop the gaming predicate (or accept it as a documented no-op).

### A.5 The IFD angle

The flake must not add import-from-derivation. Precedent for a fix already in the tree:
`modules/universal/profile/user/kdn/default.nix:97-106` replaced `pkgs.writeText` with
`builtins.toFile` because NixOS' sshd reads the file at evaluation time
(`nixos/modules/services/networking/ssh/sshd.nix`), which caused an IFD build of that file.

The one IFD-shaped helper in the overlay set is the sops `jsonTemplate.generate`: it calls
`json.generate`, then `builtins.readFile` (`modules/den/aspects/security-secrets-sops.nix:298-305`;
old `modules/universal/security/secrets/sops/default.nix:196-210`). The den router already replaced
this shape with `builtins.toJSON` to drop the IFD
(`modules/den/aspects/net-router/json-template.nix:14-22`). If the shared variant bakes
`jsonTemplate`, bake the `builtins.toJSON` version. Otherwise a consumer call re-introduces an IFD
build. Nothing else in the proposed set reads a derivation at evaluation time.

Open questions I could not settle:

- **devenv CLI pinning.** The root `devenv.nix` is driven by the devenv CLI, which builds its own
  pkgs before the flake evaluates. Verify whether devenv has a supported way to accept an external
  pkgs on the CLI path. If not, document the CLI shell as a separate, unpinned evaluation.
- **HM `useGlobalPkgs = true` behaviour.** It is source-verified (`home-manager/nixos/common.nix:45`)
  but its eval cost is unmeasured. Confirm on one NixOS host.
- **`nix-darwin` machine verification.** Source-verified only (A.3).

---

## B. Design options

### Option 1 — Isolated den modules root as a new target (the user's proposal)

A second `evalModules` root, own directory, own file, one class `pkgs`, one namespace, no batteries.
It produces `<flake>.pkgs.<arch>.<variant>`.

- **Pros.** Isolation: the `pkgs` concern never enters `den.ful.kdn` or the adopter surface. Variant
  composition is explicit (a `cuda` aspect includes `default`). One root means one place to audit.
  The output contract (`flake.pkgs.<arch>.<variant>`) is independent of how it is produced, so the
  producer can be swapped later.
- **Cons.** A second den library evaluation on the path that computes `flake.pkgs`. den's aspect
  machinery is built for module *configs*, so producing a package-set *value* needs a small class
  module that does `import inputs.nixpkgs`. More files than a plain function.

### Option 2 — Extend the existing den tree with a `pkgs` class/aspect

Add `den.classes.pkgs` and a `pkgs` output to `modules/den/flake-module.nix`.

- **Pros.** No second den evaluation. Reuses `modules/den/lib.nix` registry directly.
- **Cons.** Mixes a build-infrastructure concern into the host/aspect tree. `den.ful.kdn` is the
  exported adopter surface, so a mistake leaks (the earlier phantom `den` aspect is the precedent,
  `modules/den/classes/devenv.nix:81-85`). A `pkgs` aspect would appear beside `ca`, `gh`, `mcp`.
  This is the user's stated worry, and it is justified.

### Option 3 — Plain function, no den

`pkgsFor = { system, variant }: import inputs.nixpkgs { … }; flake.pkgs = genAttrs systems (genAttrs
variants …);` plus a thin per-host module that sets `nixpkgs.pkgs`.

- **Pros.** Lowest possible eval cost. Zero new den machinery. Trivial to audit and to measure.
  Variants are plain attrsets. The output contract is identical to Option 1.
- **Cons.** No den composition (`includes`, dedupe, excludes, policies). Variant reuse is plain
  Nix `//` and `lib.recursiveUpdate`. It does not satisfy the user's "driven by a den module"
  structure.

### Recommendation

**Option 1, implemented as a thin library-route den root, with the output contract of Option 3.**

Reasoning:

1. It satisfies the user's structural decision: an isolated root dedicated to pkgs, one target, one
   instantiation per (system, variant).
2. Isolation is the correct safety property. The exported namespace is an adopter contract, and a
   `pkgs` concern does not belong there.
3. The variant model maps directly onto den `includes`: `cuda` includes `default` plus
   `config.cudaSupport = true`. That is the "easy composition of specializations" the user asked
   for.
4. The output contract is deliberately the same as Option 3. If measurement shows the den root is
   too costly, the producer can be replaced by a plain function with **no host change**. This makes
   the recommendation low-risk: the expensive decision (the output shape) is decoupled from the
   cheap one (how the shape is computed).

Do not choose Option 2. It pays the isolation cost without the isolation benefit.

---

## C. The plan

### C.1 File layout

```
modules/den-pkgs/
├── README.md                 # architecture, the variant list, verification commands
├── flake-module.nix          # the only new import in flake.nix; declares flake.pkgs
├── registry.nix              # arch → variant list; variant name → aspect path
├── classes/pkgs.nix          # the `pkgs` class: options + the one import inputs.nixpkgs
├── variants/default.nix      # shared config + the static baked overlays
├── variants/cuda.nix         # includes default; sets config.cudaSupport = true (+ gate)
└── overlays/json-template.nix # the IFD-free helper lifted from the tree (A.5)
```

`flake.nix` gets one line in `imports` (`flake.nix:195-200`), beside `./modules/den/flake-module.nix`:

```nix
imports = [
  ./modules/den/flake-module.nix
  ./modules/den-pkgs/flake-module.nix   # new
  inputs.treefmt-nix.flakeModule
];
```

### C.2 The option namespace inside the isolated root

The root is isolated, so it needs no `kdn` alias that could collide with the host tree. Use one
namespace alias `pkgsroot` (unexported) and declare the real options under `kdnPkgs`:

```nix
# modules/den-pkgs/classes/pkgs.nix
{ config, lib, inputs, ... }:
let cfg = config.kdnPkgs; in
{
  options.kdnPkgs = {
    system = lib.mkOption { type = lib.types.str; };
    nixpkgsConfig = lib.mkOption { type = lib.types.attrs; default = { }; };
    overlays = lib.mkOption { type = lib.types.listOf lib.types.unspecified; default = [ ]; };
    # Read-only result. The one and only `import inputs.nixpkgs` in this root.
    result = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = import inputs.nixpkgs {
        inherit (cfg) system overlays;
        config = cfg.nixpkgsConfig;
      };
    };
  };
}
```

`classes/pkgs.nix` is the shared option module. Each variant is an aspect that emits a `pkgs` class
module under the `pkgsroot` namespace:

```nix
# modules/den-pkgs/variants/default.nix
{ inputs, ... }:
{
  pkgsroot.default.pkgs =
    { ... }:
    {
      kdnPkgs.nixpkgsConfig = {
        allowAliases = true;
        allowUnfree = true;
        permittedInsecurePackages = [ "litestream-0.3.13" "electron-28.3.3" "electron-27.3.11" "olm-3.2.16" ];
      };
      kdnPkgs.overlays = [
        inputs.self.overlays.default          # kdn, omp, pi, nur, microvm, ...
        (import ../overlays/json-template.nix) # IFD-free jsonTemplate
        # keepass plugin set, openvpn3 patch, python/ceph fixes: static, no host data
      ];
    };
}
```

```nix
# modules/den-pkgs/variants/cuda.nix
{ ... }:
{
  pkgsroot.cuda = {
    pkgs =
      { ... }:
      {
        kdnPkgs.nixpkgsConfig.cudaSupport = true;
        kdnPkgs.nixpkgsConfig.cudaCapabilities = [ "7.5" "8.6" ];  # example; decide per host
      };
    includes = [ pkgsroot.default ];   # den merges the default module in
  };
}
```

`cuda` names `default` in `includes`, so den merges the shared config into it and the variant never
re-states it. `den.classes.pkgs = { }` (the route at `modules/den/classes/devenv.nix:151`) tells den
the class exists; `den.lib.aspects.resolve` accepts any class name anyway
(`modules/den/README.md`, "the library route").

`flake-module.nix` then evaluates **one root per (system, variant)** and reads the result. This is
what makes "one instantiation per pair" true:

```nix
# modules/den-pkgs/flake-module.nix  (shape)
evalPair = { system, variant }:
  let
    resolved = den.lib.aspects.resolve "pkgs" den.ful.pkgsroot.${variant};
  in
  (lib.evalModules {
    specialArgs = { inherit inputs; };
    modules = [
      ./classes/pkgs.nix
      { kdnPkgs.system = system; }
      resolved
    ];
  }).config.kdnPkgs.result;

flake.pkgs = lib.genAttrs systems (system:
  lib.genAttrs registry.${system} (variant: evalPair { inherit system variant; }));
```

Each `kdnPkgs.result` holds the single `import inputs.nixpkgs` for that pair. All consumers read
`self.pkgs.<system>.<variant>`, so the thunk is shared inside one process (D.12).

### C.3 The variant model

`flake.pkgs.<arch>.<variant>`. `arch` is a supported system from `flake.nix:192`. The registry is
explicit, so a variant exists only where it makes sense:

```nix
# modules/den-pkgs/registry.nix
{
  "x86_64-linux"  = [ "default" "cuda" ];
  "aarch64-linux" = [ "default" ];
  "aarch64-darwin" = [ "default" ];
}
```

A host reads `self.pkgs.${system}.${variant}`. A missing pair is a plain `attribute missing` error,
which is the right failure. Add a `lib.throwIf` if a nicer message is wanted.

### C.4 Baked overlays

`default` bakes `self.overlays.default` (`flake.nix:238-346`) plus the static overlays from A.4:
`jsonTemplate` (toJSON form), the keepass plugin set, the openvpn3 patch, and the
`modules/universal/default.nix:167-190` Python/ceph overlays. This yields `pkgs.kdn.*`,
`pkgs.omp`, `pkgs.pi-coding-agent`, `pkgs.nixos-anywhere`, `pkgs.nix-fast-build` and the casks,
all from one instance.

`age` and `hw-gpu` are **not** baked; they are refactored per host (C.7).

### C.5 How a host opts in

The host already embeds den modules (`hosts/moss/default.nix:16-25`). Add the pinning module to that
same list. For Moss:

```nix
imports = [
  kdnConfig.self.nixosModules.default
  (kdnConfig.self.denLib.imports {
    class = "nixos";
    aspects = [ "ca-dag" "certificates" "net-rustdesk-forward" "ssh-ca" ];
  })
  # new: the pinned-pkgs module, a plain module (no den needed)
  {
    kdn.pkgs = {
      pinned = true;
      variant = "default";
    };
  }
];
```

The consumer module that turns `kdn.pkgs` into `nixpkgs.pkgs` lives once, in
`modules/universal/pkgs-pin/default.nix` (new), imported by `modules/universal/default.nix`:

```nix
# modules/universal/pkgs-pin/default.nix  (shape)
{ config, lib, pkgs, kdnConfig, ... }:
let cfg = config.kdn.pkgs; in
{
  options.kdn.pkgs.pinned = lib.mkEnableOption "use the flake-level pinned pkgs";
  options.kdn.pkgs.variant = lib.mkOption { type = lib.types.enum [ "default" "cuda" ]; default = "default"; };

  config = lib.mkIf cfg.pinned {
    nixpkgs.pkgs = kdnConfig.self.pkgs.${pkgs.stdenv.hostPlatform.system}.${cfg.variant};
    nixpkgs.overlays = lib.mkForce [ ];
    nixpkgs.config = lib.mkForce { };
    assertions = [
      { assertion = config.nixpkgs.overlays == [ ];
        message = "kdn.pkgs.pinned: overlays are baked into self.pkgs; add to a variant, not nixpkgs.overlays."; }
      { assertion = config.nixpkgs.config == { };
        message = "kdn.pkgs.pinned: nixpkgs.config is baked into self.pkgs."; }
      { assertion = config.nixpkgs.pkgs.stdenv.hostPlatform.system
                    == pkgs.stdenv.hostPlatform.system;
        message = "kdn.pkgs.pinned: the selected variant targets a different system."; }
    ];
  };
}
```

`kdnConfig` reaches the module because `modules/meta/default.nix:86-91` puts it into `specialArgs`
(the same route `modules/universal/default.nix:1-12` already uses), and `kdnConfig.self` is the
flake (`modules/meta/default.nix:95`). No new `specialArgs` is needed.

If the user prefers the pin to be **driven by a den aspect** embedded in the host (the stated
goal), the aspect can supply the same line without `kdnConfig`, because den closes over `inputs` and
`inputs.self` is the flake (`modules/den/flake-module.nix:35-37`):

```nix
# an aspect registered beside the host's other aspects
{ inputs, ... }:
{
  kdn.pkgs-pin.nixos =
    { pkgs, ... }:
    { nixpkgs.pkgs = inputs.self.pkgs.${pkgs.stdenv.hostPlatform.system}."default"; };
}
```

Moss then adds `"pkgs-pin"` to its `aspects` list (`hosts/moss/default.nix:18-23`). Both routes set
the same option, so choose one and keep it.

### C.6 The guard around the six overlay-setting aspects

Add one switch, `kdn.pkgs.pinned`. Every overlay site gets a guard:

```nix
nixpkgs.overlays = lib.mkIf (!(config.kdn.pkgs.pinned or false)) [ …existing… ];
```

Apply it to: `modules/universal/default.nix:136` and `:167-190`;
`modules/universal/security/secrets/{sops,age}/default.nix`; `modules/universal/hw/gpu/default.nix`;
`modules/universal/programs/keepass/default.nix`; `modules/universal/networking/openvpn/default.nix`.
For the den aspects, guard `modules/den/aspects/{security-secrets-sops,security-secrets-age,hw-gpu,net-openvpn,program-keepass}.nix` with the same option (an aspect may read `config.kdn.pkgs.pinned or false`).

Default `false`, so nothing changes for a host that does not opt in (constraint 4).

### C.7 Enforcement and the two refactors

- **Enforcement.** The three assertions in C.5 run on every pinned host. A stale overlay or a
  divergent config fails evaluation with an actionable message.
- **age refactor.** Replace the overlay with a wrapper package expression installed through
  `environment.systemPackages` (`lib.hiPrio`), and change the two `pkgs.sops` entries
  (`modules/universal/security/secrets/sops/default.nix:245`,
  `modules/den/aspects/security-secrets-sops.nix:280`) to the wrapper expression. Verified: those
  two lines are the only readers (A.4). This keeps one instantiation for that host.
- **hw-gpu refactor.** Keep `multiGPU.package` as a per-host `pkgs.extend` or a named variant
  (`cuda` and `gpu-supergfxctl` on `x86_64-linux`). Do not bake a laptop package into `default`.
- **Reject a missing variant.** A flake-level `lib.throwIf` in `registry.nix` when a host names a
  pair that the registry does not list.

### C.8 colmena, easykubenix and perSystem

```nix
# flake.nix
meta.nixpkgs = self.pkgs."x86_64-linux"."default";                     # was :466
meta.nodeNixpkgs."${name}".__init = self.pkgs.${host.specialArgs.kdnConfig.system}."default";  # was :481
# easykubenix (:511)
pkgs = self.pkgs.${system}."default";
# perSystem (:526)
_module.args.pkgs = self.pkgs.${system}."default";
```

`self.pkgs` is a top-level flake output (`flake.pkgs = …` in `modules/den-pkgs/flake-module.nix`).
Flake outputs are lazy, so a colmena evaluation forces each system's shared thunk once, and every
node reuses it inside that one process.

### C.9 Step-by-step migration

Order: **moss → anji → briv → brys → oams → etra.** Default behaviour stays unchanged until a host
flips `kdn.pkgs.pinned = true`.

1. Add `modules/den-pkgs/` and its `flake.nix` import. Add `modules/universal/pkgs-pin/` and its
   import. Change no host. Verify
   `nix eval --raw .#pkgs.aarch64-darwin.default.stdenv.hostPlatform.system`.
2. Add the `kdn.pkgs.pinned` guards to all six overlay sites, still default `false`. Verify a host
   that is not flipped keeps the same `environment.systemPackages` names and key option values
   (compare option values, not `drvPath`, for the reason in step 4).
3. Refactor the age wrapper to `systemPackages`/`pkgs.extend`, still default-route. Verify the
   wrapper still lands on PATH and `sops` still decrypts on one host.
4. Flip **moss** (x86_64-linux, `nixos`, den route already). Compare `environment.systemPackages`
   names and a couple of option values against the pre-flip tree (the `drvPath` trap in
   `docs/tasks/2026-09/eval-performance/research.md:786-800` makes `drvPath` invalid here).
5. Flip **anji** (`aarch64-darwin`). Remove `{ nixpkgs.system = host.system; }` for it
   (`flake.nix:451`) or guard it. Verify `nix-darwin` accepts `nixpkgs.pkgs` on the pinned rev.
6. Flip **briv** (`aarch64-linux`).
7. Flip **brys** (`x86_64-linux`, gaming). Decide the gaming `allowUnfreePredicate` (drop it, or
   accept as a no-op). Verify Steam still evaluates.
8. Flip **oams** (gaming, same decision).
9. Flip **etra** (x86_64-linux).
10. Flip the flake-level consumers (`perSystem`, `easykubenix`, `colmena`) in one change. This is the
    biggest single win (`flake.nix:466-526`).
11. Set the old `nixpkgs.overlays = [ self.overlays.default ]` sites to reject a non-empty list, and
    update the negative test (E).

Keep a per-host `kdn.pkgs.variant` that names `default` unless a host truly needs `cuda`.

---

## D. Adversarial review

A hostile review of **Option 1** (the recommendation).

### D.1 Eval recursion when `pkgs` depends on module config

- **Risk.** `kdnPkgs.result = import inputs.nixpkgs { overlays = cfg.overlays; … }` reads `config`
  while the module system is still assembling `config`. If an overlay value reads `config` that in
  turn reads `result`, evaluation loops.
- **Likelihood.** Medium on the variant side, high if a variant overlay is written carelessly.
- **Impact.** `error: infinite recursion encountered`, hard failure.
- **Mitigation.** Read `config` only in the *value* of `kdnPkgs.*`, never in the attribute *keys*
  (the rule stated at `modules/den/classes/devenv.nix:143-146`). Keep variant overlays pure
  `final`/`prev` functions (the keepass aspect already documents why: `program-keepass.nix:3-5`).
  Add a smoke check that forces `flake.pkgs.<arch>.<variant>.hello`.
- **One concrete cycle to rule out.** `default` bakes `self.overlays.default`, which reads
  `self.kdnMetaModule` (`flake.nix:209,301`). `modules/meta` reads no `self.pkgs`, so the graph is
  acyclic. Force `nix eval .#pkgs` early to prove it; a cycle would surface as infinite recursion.

### D.2 The `nixpkgs.config` assertion and `overlays` appending

- **Risk.** A pinned host that still sets `nixpkgs.config` fails the assertion
  (`nixpkgs/modules/misc/nixpkgs.nix:409-418`; nix-darwin `:319-329`). Worse, a stale
  `nixpkgs.overlays` does **not** fail: it is appended (`nixpkgs.nix:107`; nix-darwin `:103`), so
  the result silently diverges from the shared instance.
- **Likelihood.** High for overlays, because 14 sites set them today (A.1, A.4). Low for config once
  guarded.
- **Impact.** Silence is worse than failure: two hosts with the same variant can differ.
- **Mitigation.** Our own `config.nixpkgs.overlays == [ ]` assertion (C.5). It converts the silent
  case into a loud one. Document that the "mutually exclusive" claim in `definition.md` is wrong on
  these revisions.

### D.3 `hostPlatform` / cross-compilation

- **Risk.** With an external `pkgs`, the system-match assertion is disabled (`constructedByUs` is
  false, A.3). A wrong variant gives wrong-arch packages with no error.
- **Likelihood.** Low (the variant is chosen by system) but non-zero for a `cuda` variant on the
  wrong arch.
- **Impact.** Build failure late, or a broken closure.
- **Mitigation.** Assert `config.nixpkgs.pkgs.stdenv.hostPlatform.system == pkgs.stdenv.hostPlatform.system`
  (C.5). Keep cross builds (rosetta, `nix.linux-builder` at `hosts/anji/default.nix:434`) out of the
  pinned path; they are nested evals and must keep their own `hostPlatform`.

### D.4 The `cuda` variant and binary-cache hit rate

- **Risk.** `cudaSupport = true` rebuilds a large part of the closure, and `cache.nixos.org` serves
  only the default build. The cuda host compiles much of its closure.
- **Likelihood.** Certain if a host flips to `cuda`.
- **Impact.** Build time and disk, not correctness.
- **Mitigation.** Use `cuda` only on the one host that needs it. Measure the closure and the cache
  hit rate before the flip. Do not make `cuda` the default for any arch.

### D.5 nix-darwin base-system vs `nixpkgs.pkgs` on the pinned rev

- **Risk.** nix-darwin's activation scripts and `environment.systemPath` may assume a
  nix-darwin-built `pkgs` (the `pkgs.darwin.apple_sdk` shape). An externally imported nixpkgs might
  not carry nix-darwin's own overlay additions.
- **Likelihood.** Medium. nix-darwin's own overlay is in `self.overlays.default`
  (`flake.nix:243`), so the pinned set includes it. But the base `darwin` package set may need
  `nixpkgs.config` or a `dontCheck` style tweak.
- **Impact.** Activate-time failure or a missing SDK.
- **Mitigation.** The shared variant must apply `inputs.nix-darwin.overlays.default` (it already is
  in `self.overlays.default`). Verify anji by comparing `environment.systemPackages` names and
  running the activation in the darwin VM harness. If it fails, fall back to the local
  `nixpkgs.hostPlatform` route for darwin and document the exception.

### D.6 Home Manager `useGlobalPkgs`

- **Risk.** Flipping `useGlobalPkgs` from `false` (`modules/universal/default.nix:96`) to `true`
  changes HM option semantics: HM `nixpkgs.*` options stop existing
  (`home-manager/nixos/common.nix:95-101`), so the `_hm-bootstrap.nix:26-44` bridge would abort
  with "option does not exist" if left in.
- **Likelihood.** High.
- **Impact.** Evaluation failure.
- **Mitigation.** Guard `_hm-bootstrap.nix` on `!config.kdn.pkgs.pinned`, and set
  `useGlobalPkgs = !config.kdn.pkgs.pinned` in the same place. Test on moss first.

### D.7 devenv's own pkgs handling and `pkgs.kdn.*` / `pkgs.omp`

- **Risk.** devenv's CLI path builds its own pkgs and never sees `flake.pkgs`. On the eval path,
  `devenv.overlays` (`<devenv>/src/modules/top-level.nix:102-115`) must stay empty or it re-extends.
- **Likelihood.** High for the CLI path.
- **Impact.** The devenv shell stays unpinned; the goal is only partly met.
- **Mitigation.** Pin the den/devenv *evaluation* (`classes/devenv.nix:48`). For the CLI, document
  it as unpinned, or find a supported external-pkgs hook. Verify `pkgs.kdn.*` and `pkgs.omp` still
  appear in the shell (they come from `self.overlays.default`, baked into the variant).

### D.8 Colmena `nodeNixpkgs`

- **Risk.** colmena may expect `meta.nixpkgs` and `meta.nodeNixpkgs` to be *distinct* per node for
  cross-system fleets. Our fleet is mixed: `x86_64-linux` and `aarch64-linux` nodes.
- **Likelihood.** Medium.
- **Impact.** A node evaluates with the wrong arch's packages.
- **Mitigation.** `nodeNixpkgs.<host>` selects `self.pkgs.${system}.default` per host, not one
  global value. `meta.nixpkgs` (colmena's CLI) stays `x86_64-linux`.

### D.9 The sops `jsonTemplate` overlay is host-content-specific

- **Risk.** If the overlay closure actually reads host data, it cannot bake.
- **Likelihood.** Low. Source shows `jsonTemplateOverlayFor lib` uses only `lib`, `final.formats.json`
  and `prev.writeText` (`modules/den/aspects/security-secrets-sops.nix:285-307`).
- **Impact.** If wrong, the "one pkgs" claim breaks.
- **Mitigation.** Keep the baked helper pure. If a host needs host-specific JSON, generate it in the
  module, not the package set (the den router already does this,
  `modules/den/aspects/net-router/json-template.nix`).

### D.10 Stale per-module overlays silently diverge

- **Risk.** A future module adds `nixpkgs.overlays` without the guard. It appends silently.
- **Likelihood.** Medium over time.
- **Impact.** Drift that no one sees.
- **Mitigation.** The `overlays == [ ]` assertion (D.2), plus a check in `checks/` that evaluates a
  bare pinned host and asserts `nixpkgs.overlays == [ ]` and `nixpkgs.config == { }`.

### D.11 One pkgs per system vs per `allowUnfreePredicate`

- **Risk.** Gaming hosts set `allowUnfreePredicate`
  (`modules/universal/profile/machine/gaming/default.nix:33`). If that must stay, `x86_64-linux` has
  two configs.
- **Likelihood.** Low. `allowUnfree = true` already admits the Steam names, and the den port drops
  the predicate (`modules/den/aspects/profile-gaming.nix:24-27`).
- **Impact.** If wrong, a second instantiation for two hosts.
- **Mitigation.** Drop the predicate and verify Steam. If it must stay, make gaming a named variant
  (`gaming`) and count it as a deliberate second instance.

### D.12 Measurement validity

- **Risk.** Nix memoises per process. A single `nix eval` of many hosts shares the `self.pkgs.<sys>`
  thunk; six separate `nixos-rebuild` runs do not. A measurement that mixes the two overstates the
  win.
- **Likelihood.** Certain if the protocol is careless.
- **Impact.** A false conclusion, then a wasted refactor.
- **Mitigation.** Report two numbers: (1) one process, many hosts (the sharing case), and (2) N
  processes (the no-sharing case). State plainly that the second does **not** improve from the flake
  pin, except through HM `useGlobalPkgs` and colmena's single-process hive. Use
  `hack/eval-profile.sh` and pin one revision (E).

### D.13 Summary of likelihood × impact

| Risk | Likelihood | Impact | Mitigation status |
| --- | --- | --- | --- |
| D.2 overlays appended silently | High | High | Assertion (C.5) |
| D.6 HM `useGlobalPkgs` bridge | High | High | Guard `_hm-bootstrap.nix` |
| D.5 nix-darwin base system | Medium | High | Verify on anji; fall back |
| D.7 devenv CLI | High | Medium | Document as unpinned |
| D.1 eval recursion | Medium | High | Pure overlays, value-only config reads |
| D.3 hostPlatform | Low | High | System assertion |
| D.9 jsonTemplate host data | Low | High | Pure overlay |
| D.4 cuda cache | Certain (cuda only) | Medium | Restrict to one host |
| D.8 colmena mixed arch | Medium | Medium | Per-node system selection |
| D.10 future drift | Medium | Medium | Assertion + check |
| D.11 gaming predicate | Low | Low | Drop it |
| D.12 measurement | Certain if careless | High | Two-number protocol |

---

## E. Success metrics and verification

### E.1 Prove exactly one instantiation per (system, variant)

Force the whole `flake.pkgs` output in one process and count the nixpkgs top-level calls:

```bash
nix eval --impure --trace-function-calls \
  --expr 'let f = builtins.getFlake (toString ./.); in builtins.deepSeq f.pkgs f.pkgs' \
  2>/tmp/pkgs.trace >/dev/null
grep -c 'pkgs/top-level/default.nix' /tmp/pkgs.trace
```

The count must equal `#systems × #variants` in `modules/den-pkgs/registry.nix` (3 × {default} plus
1 × {cuda} on this tree, so 4). A count above that means a second instantiation. Confirm the exact
path string on the first run and adjust the grep literal. Run the same grep on a host evaluation:

```bash
nix eval --impure --trace-function-calls \
  '.#nixosConfigurations.moss.config.system.build.toplevel.drvPath' \
  2>/tmp/moss.trace >/dev/null
grep -c 'pkgs/top-level/default.nix' /tmp/moss.trace
```

Must be `1` for a pinned host (the shared `default`), plus any nested evals you accept (record them:
`hosts/anji/default.nix:434` is one).

### E.2 Measure per-host eval time

Use the committed harness, pinned to one revision:

```bash
hack/eval-profile.sh '.#nixosConfigurations.moss.config.system.build.toplevel.drvPath'
KDN_EVAL_READ_ONLY=1 hack/eval-profile.sh '.#darwinConfigurations.anji.config.system.build.toplevel.drvPath'
```

`--read-only` measures pure evaluation with no `.drv` instantiation, which is the right comparison
for a pin (`hack/eval-profile.sh:14-16`). Repeat 5 times, idle machine (`KDN_EVAL_LOAD_MAX`), and
compare the median against the recorded baseline. For a quick sanity number without the profiler:

```bash
/usr/bin/time -f '%e s' nix eval --raw \
  '.#nixosConfigurations.moss.config.system.build.toplevel.drvPath'
```

### E.3 Measure multi-host, single command (the sharing case)

```bash
/usr/bin/time -f '%e s' nix eval --raw \
  --expr 'let f = builtins.getFlake (toString ./.); in
          toString (map (h: h.config.system.build.toplevel.drvPath)
                        (builtins.attrValues f.nixosConfigurations))'
```

Run it once with the pin and once on the pre-pin revision. The delta is the shared-`pkgs` effect.
Then run the same hosts as separate processes:

```bash
for h in moss brys oams etra; do
  /usr/bin/time -f "$h %e s" nix eval --raw \
    ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath"
done
```

Report both. The separate-process sum is the honest user-facing number; it improves only through HM
`useGlobalPkgs` and colmena's single-process hive, not through cross-process sharing
(D.12).

### E.4 Negative test

Reuse a real host's modules so `kdn.pkgs` and `kdnConfig.self` exist, then add one offending
module:

```bash
nix eval --impure --expr '
  let f = builtins.getFlake (toString ./.);
      h = f.hostConfigurations.moss;
  in (f.lib.nixosSystem {
    inherit (h) system specialArgs;
    modules = h.modules ++ [
      { kdn.pkgs.pinned = true; }
      { nixpkgs.overlays = [ (final: prev: { }) ]; }
    ];
  }).config.system.build.toplevel.drvPath'
```

Must fail with the "overlays are baked into self.pkgs" message. Swap the offending module for
`{ nixpkgs.config.allowUnfree = true; }` to prove the "nixpkgs.config is baked" message.

### E.5 Closure sanity

A pinned host must still build its toplevel, and devenv must still enter. Compare option values,
not `drvPath` (the `self` leak makes `drvPath` invalid; `docs/tasks/2026-09/eval-performance/research.md:786-800`):

```bash
nix eval --json '.#nixosConfigurations.moss.config.environment.systemPackages' \
  --apply 'map (p: p.name or "?")' | jq -S . > /tmp/moss-after.json
# diff against the /tmp/moss-before.json captured before the flip
```

Run `nix run '.#checks.<system>.bundle-core'` (11 s) as the tripwire, and
`nix build --no-eval-cache -L '.#checks.<system>.bundle-pkgs'` after the overlay changes
(`checks/README.md:34-42`). Do not run a bare `nix flake check` (it takes ~15 minutes).

### E.6 Acceptance numbers

1. `grep -c` in E.1 equals `#systems × #variants`, and `1` per pinned host.
2. Median per-host eval time drops versus the recorded baseline (report the percentage; do not set
   an absolute target before the first measurement).
3. The single-command multi-host eval (E.3) drops more than the separate-process sum, which proves
   sharing.
4. Both negative tests (E.4) fail with the new message.
5. A pinned host's `environment.systemPackages` name set matches the pre-pin set, and devenv enters.
