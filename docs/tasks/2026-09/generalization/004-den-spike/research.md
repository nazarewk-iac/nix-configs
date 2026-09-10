---
type: Research
description: Measured outcome of the decisive phase of the denful/den evaluation spike, per criterion, with commands and outputs.
authored_by: agent
timestamp: 2026-09-10T07:00:00+02:00
---

# den spike — decisive phase

Task: [definition.md](definition.md)

Every test ran in scratch flakes under `/tmp/den-spike/`. No file in this repository changed.
No `jj` or `git` mutation ran. No `nix` command used `.#` or `git+file:` inside the repository.

## Verdicts

| Criterion | Verdict |
|---|---|
| 2 — an external adopter imports a resolved aspect, with no den in their own code | **PASS, with two recorded limits** |
| 1 — a `devenv` class can exist | **PASS** |
| 3 — conditional-imports requirement | **BLOCKED on checkpoint 005** |
| 4 — the 1→N mixed-aspect collision | **REFUTED — it does not reproduce** |

Recommendation: **continue to the additive `modules/den/` phase.** Read
[Recommendation](#recommendation) for the conditions.

## Revisions under test

| Component | Revision | Date | Note |
|---|---|---|---|
| den `main` | `d50f0fce6fc1a8ba00fd0d310746d0e8ecc2f70d` | 2026-09-04 | `fix: collapse agreeing definitions in the route merge (#674) (#675)` |
| den `v0.18.0` | `5df0987658d6e44268abba953406480e9f066928` | 2026-06-16 | the tag commit; the task file records the release as 2026-06-23 |
| `denful/nix-effects` | `c3c68a45deb892d028711eeff8b80937e30a90dd` | 2026-05-13 | den's own `templates/ci/flake.lock` pins this |
| `cachix/devenv` | `190959a9a4bb52d4802f076a90c3c4e3aa2e6fa2` | 2026-09-07 | the revision this repository pins in both `flake.lock` and `devenv.lock` |
| nixpkgs (criteria 2, 4) | `path:/nix/store/j0xsrr9a6dx6b4rf3lnzmak43ff82cs6-source` | — | `NixOS/nixpkgs` `d6524aaca2ff07876657ae2b323f24be4874944b`, already in the store |
| nixpkgs (criterion 1) | `cachix/devenv-nixpkgs/256551e45f6303e142ab4a98be1bf243feb77dc0` | 2026-08-26 | devenv needs its own channel |

Evaluator: `nix (Lix, like Nix) 2.95.2`, `aarch64-darwin`.

`git log -1 --format='%H %ci %s'` in `/tmp/den-spike/den-git`:

```
d50f0fce6fc1a8ba00fd0d310746d0e8ecc2f70d 2026-09-04 14:34:20 -0700 fix: collapse agreeing definitions in the route merge (#674) (#675)
```

`den` itself declares **no flake inputs**. `flake.nix` is two lines: `outputs = _: import ./nix;`.

---

## Criterion 2 — PASS, with two recorded limits

### Test shape

Two flakes:

- `/tmp/den-spike/c2/producer/` — the den repository. It holds `den`, `nix-effects` and
  `nixpkgs` as inputs. It exports `nixosModules.<case> = den.lib.aspects.resolve "nixos"
  den.aspects.<case>`.
- `/tmp/den-spike/c2/adopter/` — the adopter repository. Its only inputs are `nixpkgs` and
  the producer. **It has no `den` input and no `nix-effects` input.** It reads each exported
  module back two ways: through a bare `lib.evalModules`, and through a real
  `nixpkgs.lib.nixosSystem`.

`/tmp/den-spike/c2/producer-v18/` and `/tmp/den-spike/c2/adopter-v18/` repeat the same test
against den v0.18.0.

### The seven cases

| Case | What it exercises | Result at the adopter |
|---|---|---|
| A | one plain option, no den feature | **survives** |
| B | the aspect declares its own option and reads it back | **survives** |
| C | one aspect depends on a second aspect through `includes` | **survives** |
| D | the aspect needs `pkgs` | **survives** |
| E | the aspect reads entity data (`{ host, ... }`) | **silently drops to a no-op** |
| F | the aspect includes a den battery (`den.batteries.hostname`) | **silently drops to a no-op** |
| G | mixed aspect: both a `nixos` key and a `homeManager` key | the `nixos` half **survives** |

### Verified — the plain `lib.evalModules` read-back

```
cd /tmp/den-spike/c2/adopter && for c in caseA caseB caseC caseD caseE caseF caseG; do printf "%-8s " "$c"; nix eval --json ".#plain.$c"; done
```

```
caseA    {"hostName":"unset","variables":{"SPIKE_A":"a"}}
caseB    {"hostName":"unset","variables":{"SPIKE_B":"read-b-default"}}
caseC    {"hostName":"unset","variables":{"SPIKE_C":"c","SPIKE_C_DEP":"dep"}}
caseD    {"hostName":"unset","variables":{"SPIKE_D":"hello"}}
caseE    {"hostName":"unset","variables":{}}
caseF    {"hostName":"unset","variables":{}}
caseG    {"hostName":"unset","variables":{"SPIKE_G":"g"}}
```

### Verified — the real `nixosSystem` read-back

All seven modules go into one `nixpkgs.lib.nixosSystem` in the den-free flake:

```
cd /tmp/den-spike/c2/adopter && nix eval --json '.#nixosAll'
```

```
{"EDITOR":"nano",…,"SPIKE_A":"a","SPIKE_B":"read-b-default","SPIKE_C":"c","SPIKE_C_DEP":"dep","SPIKE_D":"hello","SPIKE_G":"g",…}
```

`SPIKE_E` and `SPIKE_F` are absent. Nothing warns and nothing fails.

### Verified — v0.18.0 gives byte-identical results

```
cd /tmp/den-spike/c2/adopter-v18 && for c in caseA … caseG; do nix eval --json ".#plain.$c"; done
```

The seven lines match the `main` run exactly. The `nixosAll` output matches too. So the
2.5 months of unreleased drift change nothing for these cases.

### Verified — what `resolve` returns

```
cd /tmp/den-spike/c2/producer && nix eval --json '.#nixosModules.caseA' --apply 'm: { attrs = builtins.attrNames m; importCount = builtins.length m.imports; }'
{"attrs":["imports"],"importCount":1}

nix eval --json '.#nixosModules.caseE' --apply 'm: { attrs = builtins.attrNames m; importCount = builtins.length m.imports; }'
{"attrs":["imports"],"importCount":0}

nix eval --json '.#nixosModules.caseF' --apply 'm: { attrs = builtins.attrNames m; importCount = builtins.length m.imports; }'
{"attrs":["imports"],"importCount":0}
```

`resolve` returns exactly `{ imports = [ … ]; }`. A parametric aspect returns
`{ imports = [ ]; }` — an empty module. **The drop is silent.** That is the first limit.

### Verified — the same aspects work inside den

To prove that cases E and F are valid aspects, the producer also builds a real den host:

```
cd /tmp/den-spike/c2/producer && nix eval --json '.#inDen'
{…,"SPIKE_A":"a","SPIKE_D":"hello","SPIKE_E":"igloo",…}

nix eval --json '.#inDenHostName'
"igloo"
```

Inside den, `SPIKE_E` reads `igloo` and the `hostname` battery sets
`networking.hostName = "igloo"`. Across the `resolve` boundary both vanish.

### Verified — two ways to carry entity data across the boundary

**Route 1 — the producer binds an entity first.** This is den's own production path
(`modules/outputs.nix` and `nix/lib/entities/_types.nix` both use it):

```nix
resolve "nixos" (den.lib.resolveEntity "host" { host = { name = "bound-by-producer"; aspect = den.aspects.caseE; users = { }; homes = { }; class = "nixos"; system = "x86_64-linux"; hostName = "bound-by-producer"; }; })
```

```
cd /tmp/den-spike/c2/adopter && nix eval --json '.#nixos.caseEbound'
{…,"SPIKE_E":"bound-by-producer",…}
```

It works. But the **producer** invents the host data, not the adopter. An adopter cannot pass
their own host name into a pre-resolved module. That is the second limit.

A first attempt with a shorter host record failed with `error: attribute 'users' missing`. So
a hand-built entity record must carry `users`, `homes`, `class`, `system` and `hostName`.

**Route 2 — export a whole host.** `den.hosts.<system>.<name>.mainModule` crosses the
boundary and keeps its entity data:

```
cd /tmp/den-spike/c2/adopter && nix eval --json '.#nixos.wholeHost'
{…,"SPIKE_A":"a","SPIKE_D":"hello","SPIKE_E":"igloo",…}
```

The granularity is one whole host, not one aspect. den's own maintainer says in discussion
#124 that host sharing was never a goal.

### Verified — the adopter's lock still records den

```
jq -r '.nodes | keys' /tmp/den-spike/c2/adopter/flake.lock
["aspectlib","den","nix-effects","nixpkgs","root"]

jq -r '.nodes.root.inputs' /tmp/den-spike/c2/adopter/flake.lock
{"aspectlib":"aspectlib","nixpkgs":"nixpkgs"}
```

So "no den input" holds only for the adopter's **root** inputs and their **code**. den stays a
transitive lock node, and the adopter's evaluation forces the den source. A Nix module is a
closure, so no serialisation can remove that. Treat the claim as: the adopter writes no den
code and learns no den concept. The adopter still fetches den.

### Verified — den fetches `nix-effects` at evaluation time, outside any lock

`nix/lib/fx.nix` in den:

```nix
lock = builtins.fromJSON (builtins.readFile ../../templates/ci/flake.lock);
locked = lock.nodes.nix-effects.locked;
nix-effects = builtins.fetchTarball {
  url = "https://github.com/${locked.owner}/${locked.repo}/archive/${locked.rev}.zip";
  sha256 = locked.narHash;
};
nfx = import nix-effects { inherit lib; };
…
inputs.nix-effects.lib or nfx
```

`/tmp/den-spike/c2/producer-nofx/` drops the `nix-effects` input. den still evaluates:

```
cd /tmp/den-spike/c2/producer-nofx && nix eval --json '.#aspectNames'
["caseA","caseB","caseC","caseCdep","caseD","caseE","caseF","caseG","igloo","tux","wsl-host-aspect"]

jq -r '.nodes | keys' /tmp/den-spike/c2/producer-nofx/flake.lock
["den","nixpkgs","root"]
```

The fetch itself, reproduced by hand:

```
nix eval --impure --json --expr 'let lock = builtins.fromJSON (builtins.readFile /nix/store/6zvwis9ybb9iy0vypb7v798109gshffl-source/templates/ci/flake.lock); l = lock.nodes."nix-effects".locked; in { url = …; path = builtins.fetchTarball { … }; }'
{"path":"/nix/store/a52bf3fnfdyykhgp1fhf7hspdbsqk0f2-source","rev":"c3c68a45deb892d028711eeff8b80937e30a90dd","url":"https://github.com/denful/nix-effects/archive/c3c68a45deb892d028711eeff8b80937e30a90dd.zip"}
```

Lix 2.95.2 accepts the SRI `narHash` as `fetchTarball`'s `sha256`. So this is not a Lix defect.
It is a hermeticity defect: a network dependency that no lock file records. Every consumer must
declare `nix-effects` as its own input to close it.

### The "Internal" label — a stability warning, not a correctness warning

Evidence, all verified against den `main`:

- `docs/src/content/docs/reference/lib.mdx:24-27` labels `resolve` `**Internal.**`. Exactly
  four labels exist in the whole `docs/` tree, all four in that file, all four on the
  `resolve` family (`resolve`, `resolveImports`, `resolveWithPaths`, `resolveWithState`).
- `docs/src/content/docs/guides/debug.md:102-104`: "Note: `den.lib.aspects.resolve` is internal
  to the pipeline. The examples below are useful for debugging but should not be used in
  production configurations."
- den's own output generator calls it. `modules/outputs.nix:9,28`:
  `flakeModule = den.lib.aspects.resolve "flake" (den.lib.resolveEntity "flake" { });`. Every
  den flake's outputs pass through this call.
- The documented alternative is the same code. `nix/lib/entities/_types.nix:38-60` defines
  `mainModule` as a one-line projection of `resolveWithPaths`, and marks it
  `internal = true; visible = false;`.
- `docs/src/content/docs/explanation/library-vs-framework.mdx` (sidebar-linked, badged
  `advanced`, rewritten by the author on 2026-06-04) recommends
  `den.lib.aspects.resolve class aspect` with **no** caveat, under the heading
  "**Library only**".
- `reference/lib-deprecated.mdx` never mentions `aspects.resolve`. There is **no** `CHANGELOG`
  file anywhere in the repository.
- One commit added both labels: `6254414` (2026-05-09) `feat: fx effects pipeline — replace
  legacy resolver (#475)`. `git log -S'**Internal.** Resolves an aspect'` returns only that
  commit. The same commit silently changed the arity from three arguments to two.
- v0.18.0 → `main`: `git diff 5df0987 d50f0fc -- nix/lib/aspects/default.nix` changes **one**
  line, and `resolve = fxResolveTree;` is byte-identical. `nix/lib/aspects/fx/resolve.nix`
  changes 199 lines and deletes 85, but the `fxResolve` entry point and its comment stay
  identical.

Read it as: the return contract (`{ imports = […]; }`) held across one release and 2.5 months.
The author reserves the right to change it, with no changelog and no deprecation path. The
arity already changed once, silently.

**One narrow correctness caveat.** Pass a bare `den.aspects.<x>` and `resolve` reads
`resolved.__scopeHandlers or { }` (`nix/lib/aspects/default.nix:58`), so it gets no entity
context, no schema includes and no collision policy. Cases E and F measure exactly that.
Pass `den.lib.resolveEntity "<kind>" ctx` and you are on den's own production path.

### Discussion #569 — verified, still unanswered

| Field | Value |
|---|---|
| Title | `Importing den aspects in non-den configuration` |
| Created | 2026-05-24 |
| Author | `basbebe`, `authorAssociation: NONE` |
| Accepted answer | **none** (`isAnswered: false`) after 3.5 months |
| Comments | 3 |

The question, verbatim: "Say I have a nix config repo (a) making use of den aspects for defining
hosts and users. If I wanted to import some of these definitions as 'traditional' nixosModules
in another config repo (b) which doesn't use den: How would I currently do that?"

Two maintainers replied. Neither reply is accepted.

- `theutz` (COLLABORATOR): "Technically, you can resolve a set of aspects to any flake output,
  including nixosModules."
- `vic` (MEMBER, the project author): "You can [manually resolve an aspect] into a module." He
  linked the `guides/debug/#manually-resolve-an-aspect` anchor — the same anchor that carries
  the "should not be used in production configurations" note, written 15 days earlier. He did
  not mention the caveat.
- `landure` (NONE), 2026-06-22, posts a recipe over `den.aspects` that works for unconditional
  modules, then asks how to avoid infinite recursion for conditional ones. **No reply.**

A full-text search across all 154 discussions for `homeModules` returns exactly one hit — #569.
So no maintainer has committed to this route. Nothing was posted anywhere during this spike.

### den offers no module-output route of its own

`grep -rn "homeModules\|darwinModules" nix/ modules/ docs/ templates/` returns zero hits.
Every `nixosModules` hit is den **consuming** a third-party module. den's outputs are `lib`,
`namespace`, `flakeOutputs`, `nixModule`, `templates`, `packages`, `devShells`, `flakeModule`,
`flakeModules` and `modules.flake`.

One documented, CI-covered route emits a raw module list to a flake attribute:
`den.lib.policy.instantiate` with a custom `intoAttr`. See
`docs/src/content/docs/reference/policies.mdx:158-171` and `templates/terranix-demo/`. It works
at whole-entity granularity, not per aspect.

---

## Criterion 1 — PASS

### devenv is a plain `lib.evalModules` target

Verified by reading `flake.nix` in `/nix/store/rsycyv3cahyz5bsvyl99w5m0qfg19h9v-source` (devenv
`190959a9`). `devenv.lib.mkEval` is a thin shim:

```nix
project = lib.evalModules {
  class = "devenv";
  inherit modules specialArgs;
};
```

A third party reproduces all of it. The minimal recipe:

| Requirement | Value |
|---|---|
| entry module | `<devenv-src>/src/modules/top-level.nix` |
| `class` | `"devenv"` (cosmetic; it still works without) |
| `specialArgs.inputs` | **mandatory key**, may be `{ }` |
| `pkgs` | through `_module.args.pkgs` or `specialArgs` |
| `devenv.root` | **mandatory**, no default |
| `devenv.tmpdir` | **mandatory** unless `devenv.flakesIntegration = true` |
| shell attribute | `config.shell` |

No `--impure`, no devenv CLI, no `containers` input and no `git-hooks` input. No CppNix-only
builtin appears in `src/modules/`. Every `builtins.getEnv` call site tolerates an empty value.
Do **not** set `flakesIntegration = true` without an explicit root: `flake-compat.nix` then
asserts `devenv was not able to determine the current directory.`

### A `den.classes.devenv` exists and produces a real shell

`/tmp/den-spike/c1/devenv-class.nix` is the whole class — one declaration plus one policy:

```nix
den.classes.devenv = { };

den.policies.host-to-devenv = { host, ... }: [
  (den.lib.policy.instantiate {
    name = "${host.name}-devenv";
    class = "devenv";
    instantiate = { modules, ... }: (lib.evalModules {
      class = "devenv";
      specialArgs = { inputs = { }; };
      modules = [
        (inputs.devenv-src + "/src/modules/top-level.nix")
        { _module.args.pkgs = import inputs.nixpkgs { system = host.system; };
          devenv.root = "/tmp/den-spike/c1";
          devenv.tmpdir = "/tmp";
          name = "${host.name}-devenv"; }
      ] ++ modules;
    }).config;
    intoAttr = [ "devenvShells" host.name ];
  })
];

den.schema.host.includes = [ den.policies.host-to-devenv ];
```

Verified — den accepts the class:

```
cd /tmp/den-spike/c1 && nix eval --json '.#denClassNames'
["apps","checks","darwin","devShells","devenv","hjem","homeManager","legacyPackages","maid","nixos","os","packages","user","wsl"]
```

Verified — three routes each produce a real shell derivation path:

```
# route 1 — resolve the aspect for the class, then feed devenv
nix eval --raw '.#shellADrv'
/nix/store/lmm6k18dyhjsf7r0wryxpkc9s4kwm66y-den-shell-a.drv

nix eval --json '.#shellAPackages'
["hello-2.12.3","process-compose-1.120.0","pkg-config-wrapper-0.29.2","apple-sdk-14.4"]

# route 2 — a den host aspect with includes and host-parametric content
nix eval --raw '.#shellHostDrv'
/nix/store/6b8v1pg9s2wfmkb9j0a51aha1nwzhmls-den-shell-host.drv

nix eval --json '.#shellHostEnv'
{"SPIKE_DEP":"dep","SPIKE_HOST":"igloo","SPIKE_SHELL":"a"}

# route 3 — den's own instantiate policy lands the shell in a flake output
nix eval --raw '.#instantiatedDrv'
/nix/store/pr717adbnas22kq7kp3csmkgfi3r2ndh-igloo-devenv.drv

nix eval --json '.#instantiatedEnv'
{"SPIKE_DEP":"dep","SPIKE_HOST":"igloo","SPIKE_SHELL":"a"}
```

Route 2 and route 3 both carry `SPIKE_HOST` — so a devenv aspect reads entity data, and
`includes` composition works inside the class.

Verified — v0.18.0 gives the **same derivation path**:

```
cd /tmp/den-spike/c1-v18 && nix eval --raw '.#instantiatedDrv'
/nix/store/pr717adbnas22kq7kp3csmkgfi3r2ndh-igloo-devenv.drv

nix eval --json '.#instantiatedEnv'
{"SPIKE_DEP":"dep","SPIKE_HOST":"igloo","SPIKE_SHELL":"a"}
```

No shell was built. Only `nix eval` on `drvPath` ran.

### Correction to the task file

The task file expects "~15 lines that copy" `templates/flake-parts-modules/modules/classes/devshell.nix`.
That template routes into flake-parts. devenv needs the `policy.instantiate` shape from
`templates/terranix-demo/modules/terranix.nix` instead, because devenv is a separate
`evalModules` universe, not a flake-parts option tree. The line count is right; the template
to copy is the other one.

---

## Criterion 3 — BLOCKED

Checkpoint 005 has not yet written the conditional-imports requirement as a testable statement.
No test ran. Nothing new to record.

---

## Criterion 4 — REFUTED

`/tmp/den-spike/c4/` holds a host with **two** users, both with `classes = [ "user"
"homeManager" ]`. One mixed aspect `mixed2` carries a `nixos` key that sets
`boot.kernelPackages` and a `homeManager` key. Both users include that one aspect.

Verified — the host evaluates:

```
cd /tmp/den-spike/c4 && nix eval --json '.#hmUsers'
["alice","bob"]

nix eval --json '.#kernelPackages'
"6.18.50"
```

No `The option 'boot.kernelPackages' is defined multiple times` error appears. Verified on
**both** revisions:

```
cd /tmp/den-spike/c4-v18 && nix eval --json '.#kernelPackages'
"6.18.50"
```

Verified — the user halves arrive per user:

```
nix eval --json '.#aliceEnv'
{"LOCALE_ARCHIVE_2_27":"…","SPIKE_MIXED2":"user"}

nix eval --json '.#bobEnv'
{"LOCALE_ARCHIVE_2_27":"…","SPIKE_MIXED2":"user"}
```

### The collision message is still reachable, for a real conflict

An intermediate run had **two different** aspects set `boot.kernelPackages`. den then reports:

```
error: The option `boot.kernelPackages' is defined multiple times while it's expected to be unique.

Definition values:
- In `nixos@mixed2'
- In `nixos@mixed'
Use `lib.mkForce value` or `lib.mkDefault value` to change the priority on any of these definitions.
```

That is correct behaviour, and the `nixos@<aspect>` labels are a genuine diagnostic
improvement. The 1→N duplication is what no longer happens.

### One separate observation, worth a note

A mixed aspect included at **host** scope does not deliver its `homeManager` half to the host's
users. `den.aspects.mixed` sets `home.sessionVariables.SPIKE_MIXED`, and no user gets it:

```
nix eval --json '.#aliceEnv'
{"LOCALE_ARCHIVE_2_27":"…","SPIKE_MIXED2":"user"}
```

An earlier run, before `mixed2` existed, failed with
`error: The option 'home-manager.users.alice.home.stateVersion' was accessed but has no value
defined.` even though the host-scope mixed aspect sets `home.stateVersion`.

This matches den's scope partitioning: host scope and user scope are different partitions, and
`den.batteries.forward` is the documented bridge. Record it as designed behaviour, not a bug.
It does mean the same mixed aspect behaves differently at the two scopes, so a reimplementation
must choose the scope for each aspect on purpose.

---

## Risks confirmed

Against the risk list in the task definition.

| Risk | State |
|---|---|
| v0.x, no stable API | **Confirmed.** No `CHANGELOG` file exists. One commit changed `resolve`'s arity from 3 to 2 with no note. `resolve` is labelled Internal, and so is `mainModule`, the documented alternative. |
| `main` carries about 2.5 months of unreleased drift | **Confirmed, and harmless so far.** Every criterion-2 and criterion-1 measurement is identical on v0.18.0 and `main`. Criterion 1's route-3 derivation path is byte-identical. `fx/resolve.nix` changed 199/85 lines in that window, and the entry point did not. |
| Two people write about 90% of commits | Not re-measured. Unverified here. |
| The core rests on `denful/nix-effects` despite "zero dependencies" marketing | **Confirmed, and worse than stated.** den has no flake inputs, but `nix/lib/fx.nix` reaches `nix-effects` with `builtins.fetchTarball` at evaluation time, keyed off den's own `templates/ci/flake.lock`. No consumer lock records it. A consumer must declare `nix-effects` itself to close the hole. |
| den needs neither flakes nor flake-parts | **Confirmed and useful.** `den.nixModule` runs in a bare `lib.evalModules`. `templates/noflake` uses npins. |
| No documented supported route to export aspects as `nixosModules`/`homeModules` | **Confirmed.** Zero `homeModules`/`darwinModules` hits in the whole repository. Discussion #569 has no accepted answer after 3.5 months. |

### New risks this spike found

1. **`resolve` drops entity-parametric content silently.** No warning, no error — just
   `{ imports = [ ]; }`. Any reimplementation that exports aspects must add its own check that
   the resolved module is non-empty. den offers no such check.
2. **The adopter's lock still records den and `nix-effects`.** The adopter writes no den code,
   but their evaluation fetches den. Gap 12 in the hub (lock size) therefore grows by two nodes
   plus whatever den grows into.
3. **An eval-time `builtins.fetchTarball` breaks a fully offline adopter evaluation** unless the
   producer declares `nix-effects`. Always declare it.
4. **A mixed aspect behaves differently at host scope and user scope.** See criterion 4's last
   observation.

## Lix notes

No place needed an upstream Nix feature Lix lacks. Every command above ran under Lix 2.95.2 in
pure evaluation mode, except the one hand-written `--impure` reproduction of den's
`fetchTarball`. Lix accepts an SRI `narHash` string as `builtins.fetchTarball`'s `sha256`
argument. No Lix warning appeared in any run.

## Recommendation

**Continue to the additive `modules/den/` phase.** Both kill criteria clear:

- Criterion 2 passes for the shapes that matter. A resolved aspect goes into a plain
  `lib.evalModules` and into a real `nixpkgs.lib.nixosSystem` in a flake with no den input and
  no den code. Options, own-option read-back, cross-aspect `includes` and `pkgs` all survive.
- Criterion 1 passes outright. A `devenv` class is about 30 lines, and it produces a real shell
  derivation path on both revisions.
- Criterion 4 is refuted, so the strongest recorded objection is gone.

Attach four conditions to the phase.

1. **Do not build on `resolve` alone for the adopter boundary.** Add a test that asserts every
   exported module has a non-empty `imports` list. The silent-drop failure mode is the single
   most dangerous finding here.
2. **Keep every adopter-facing aspect free of entity data.** Express host-variable values as
   plain module options that the adopter sets, as case B does. That form crosses the boundary
   and it also survives a den API break.
3. **Declare `nix-effects` as an explicit input** in any repository that imports den.
4. **Do not treat criterion 6 as decided.** Checkpoint 005 must still answer criterion 3, and
   den's pre-`evalModules` resolution may or may not satisfy it.

## Central tension

> den's strongest claim would improve the creator's own ergonomics. That is not the same as
> support for external adoption. Only criterion 2 decides the second question.

Criterion 2 answers it: **the mechanism works, and nobody stands behind it.** The measurements
are clean. The maintainers point at a page that tells you not to do this, the one question that
asks for it has no accepted answer after 3.5 months, and there is no changelog to warn you when
the contract moves. So the technical risk is low and the social risk is high. The mitigation is
condition 1 and condition 2 above: own the boundary yourself, and never let an adopter's module
depend on a den concept.
