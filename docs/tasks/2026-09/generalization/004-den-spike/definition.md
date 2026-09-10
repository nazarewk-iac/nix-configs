---
type: Task
description: Evaluate the denful/den framework as the reimplementation target before any module rewrite starts, with a drop-in import test as the decisive criterion.
status: in-progress
authored_by: agent
timestamp: 2026-09-08T17:30:00+02:00
---

# 004 — den spike

Hub: [the generalization umbrella task](../definition.md). **Run this as early as possible.**
Together with 005 it gates 006.

Goal: decide whether `denful/den` can be the target framework, before anybody rewrites a module.

## Phase 1 verdict — 2026-09-10

Measured in scratch flakes under `/tmp/den-spike/`, on den `main` and on v0.18.0. Every command
and output is in [research.md](research.md). No file in this repository changed.

| Criterion | Verdict |
|---|---|
| 2 — an adopter imports a resolved aspect, with no den in their own code | **PASS**, with two limits |
| 1 — a `devenv` class can exist | **PASS** |
| 3 — the conditional-imports requirement | **BLOCKED** on 005, not tested |
| 4 — the 1→N mixed-aspect collision | **REFUTED** — it does not reproduce |

The kill criterion does not fire. So phase 2 starts: build `modules/den/` additively.

**The two limits on criterion 2.** An entity-parametric aspect (`{ host, ... }`) and a den battery
both drop to `{ imports = [ ]; }` across the boundary, with no warning and no error. The same
aspects work inside den. Two workarounds are verified: the producer pre-binds a host with
`den.lib.resolveEntity`, or the producer exports `<host>.mainModule` (whole-host granularity).
Second, den stays a transitive lock node in the adopter's own lock — a module is a closure, so no
serialization removes it. The claim holds for the adopter's code and concepts, not for their lock.

**The "Internal" label is a stability warning, not a correctness warning.** den's own
`modules/outputs.nix` calls `resolve`; the documented alternative `mainModule` is a one-line
projection of the same code and is also `internal = true`;
`explanation/library-vs-framework.mdx` recommends it with no caveat. But there is no CHANGELOG,
and commit `6254414` silently changed the arity from 3 to 2. Discussion #569 is still unanswered
after 3.5 months, and the author's only reply links the page that warns against production use.
So the technical risk is low and the social risk is high.

**A new risk this spike found.** `nix/lib/fx.nix` fetches `denful/nix-effects` with
`builtins.fetchTarball` at evaluation time, keyed off den's own vendored
`templates/ci/flake.lock`. No consumer lock records it. Reproduced with a `nix-effects`-free
flake that still evaluates. So phase 2 must declare `nix-effects` explicitly.

**Five conditions on phase 2**, from the spike and from the creator's preference:

1. Assert every exported module has a non-empty `imports` list. The silent-empty failure above is
   otherwise invisible.
2. Keep an adopter-facing aspect free of entity data. Use a plain option instead.
3. Declare `nix-effects` as an explicit input.
4. Leave criterion 3 open until 005 states the conditional-imports requirement.
5. **Ship the adopter path as a den-resolved plain module.** The creator stated the preference on
   2026-09-10: an adopter should use the den config once the spike works out. So phase 2 owns an
   adopter-facing flake output that runs `den.lib.aspects.resolve` on this side of the boundary. The
   adopter imports a plain module, and the adopter never adopts den. That is criterion 2's measured
   shape, so treat this as a deliverable, not an experiment. Condition 1 is the guard that stops the
   silent-empty failure from reaching an adopter.
   [../../../slots-for-adopters.md](../../../slots-for-adopters.md) documents the interim `mkSlots`
   route, and it must gain the den route when phase 2 lands it.

## Phase 2 — milestone 1 lands — 2026-09-10

`modules/den/` now exists. It holds the loader, one class, one aspect and one host. See
[modules/den/README.md](../../../../modules/den/README.md) for the layout, the status table and the
verification commands. Five conditions above are met: the export guard throws on an empty `imports`
list, the ported aspect takes no entity argument, and `nix-effects` is an explicit input.

**The tree is additive.** No file under `modules/slots/`, `modules/universal/` or `modules/meta/`
changed. `flake.nix` gained two inputs and one `imports` line, because a flake input cannot live
anywhere else. `flake.lock` gained exactly two nodes — den declares no flake input of its own.

| Piece | Path | Note |
|---|---|---|
| Loader and the four outputs | `modules/den/flake-module.nix` | A nested `lib.evalModules`, not a flake-parts module. |
| `devenv` class | `modules/den/classes/devenv.nix` | den ships none. 13 of 18 slots need it. |
| First aspect | `modules/den/aspects/rosetta-builder.nix` | Core options only. The guest-size options stay in the slot. |
| First devenv aspect | `modules/den/aspects/gh.nix` | A full port of `modules/slots/gh/`. |
| Parallel entities | `checks/den-mvp/{host-darwin,host-nixos,devenv}/` | They evaluate and build. None activates. |
| Build gate | `checks.<system>.den-mvp` | The current architecture. `.all` covers every system. |

**The entities live at `checks/den-mvp/`, not in `hosts/`.** They build and never activate, so they
are test artifacts, and `checks/` states that in the path. `hosts/` is wrong for a second reason:
every entry `flake.hostConfigurations` keeps goes through `modules/meta`, and den replaces that
pre-pass. A den host that inherits `modules/meta` proves nothing. See
[checks/den-mvp/README.md](../../../../checks/den-mvp/README.md).

Seven commands verify the milestone. Each one passed:

```bash
nix eval --json '.#denModules.rosetta-builder' --apply 'm: builtins.length m.imports'
nix eval --json '.#denModules.gh' --apply 'm: builtins.length m.imports'
nix eval --raw '.#denConfigurations.host-darwin.config.system.build.toplevel.drvPath'
nix eval --raw '.#denConfigurations.host-nixos.config.system.build.toplevel.drvPath'
nix eval --json '.#denDevenvShells' --apply builtins.attrNames
nix build  '.#checks.aarch64-darwin.den-mvp'
nix eval --json '.#hostConfigurations' --apply builtins.attrNames     # no den entity present
```

**The first slot-against-den comparison ran, and it agrees.** `anji` against `host-darwin`:
`config.nix-rosetta-builder` is identical, and so is
`config.nix.settings.builders-use-substitutes`. `config.nix.buildMachines` differs, because `anji`
also gets personal remote builders from `modules/universal/profile/remote-builders/`. den ports none
of that tree, so that difference is expected.

**Four facts the milestone measured**, each one a trap for the next milestone:

1. `den.flakeModule` declares **no** `flake.<output>` option. Each output name needs its own
   declaration. den ships `inputs.den.flakeOutputs.<name>` for the names it knows. A custom class
   output such as `devenvShells` needs a hand-written `lib.mkOption`.
2. den calls `instantiate { modules = [ … ]; }` and never passes `system`. Its darwin default is
   `inputs.darwin.lib.darwinSystem`, and this repo names that input `nix-darwin`. So the host
   overrides `instantiate` instead of an input alias.
3. A bare nix-darwin host needs `system.primaryUser` and `system.stateVersion`.
   `modules/universal` supplies neither on its own.
4. A build-only NixOS host needs a root `fileSystems."/"` (a `tmpfs` names no hardware),
   `boot.loader.grub.enable = false` (GRUB is on by default and then asserts a non-empty `devices`),
   and `system.stateVersion`.

**Criterion 2 passes, and den also runs as a plain library.** `den.nixModule inputs` is a second
entry point. It imports four files and exposes exactly `{ aspects, lib, policies }` — no
`den.hosts`, no `den.schema`, no `den.classes` and no `den.default`. `den.flakeModule` is what
imports all of den's `modules/` tree, and the batteries live there. `den.lib.aspects.resolve
"<class>" <aspect>` takes an arbitrary class name and needs no entity. den's own CI asserts the
shape in `templates/ci/modules/internal-api/den-as-lib.nix`.

Measured on 2026-09-10, for both ported aspects, the library route and the `flakeModule` route give
one **identical** `drvPath`:

| aspect | class | library-mode result | identical `drvPath` |
|---|---|---|---|
| `gh` | `devenv` | `gh-2.100.0` in the shell, `claude.code.enable = true` | yes |
| `rosetta-builder` | `darwin` | `nix.buildMachines` carries `aarch64-linux x86_64-linux` | yes |

The `rosetta-builder` test used a bare `nix-darwin.lib.darwinSystem` with no `modules/universal`, no
`mkSlots` and no `kdnConfig` — the real adopter shape. Three limits hold: the consumer must pass
`specialArgs.inputs` itself; library mode covers aspects and not entities, because `den.schema.host`
is absent; and two simple aspects are not a full sample.

**Library mode now ships as `flake.denLib`.** `modules/den/lib.nix` holds it, and it owns the aspect
registry too, so the library route and the `flakeModule` route read one list. The thin wrapper is
one call, and it drops straight into any target module:

```nix
imports = inputs.nix-configs.denLib.imports { class = "devenv"; aspects = [ "gh" ]; };
```

The raw machinery sits beside it — `nixModule`, `eval`, `resolve` and `aspectModules`. This
repository's own entities keep the `den.flakeModule` route, because entity resolution needs it.

Two guards protect the wrapper, both measured on 2026-09-10. An unknown aspect name throws when the
caller builds the list, not later when the module system forces one element. And a **whole-aspect**
function — `{ host, ... }: { name = …; devenv = …; }` — resolves to `{ imports = [ ]; }`, so
`resolve` throws. This sharpens condition 2 above: a **per-target** function
(`devenv = { host, ... }: …`) resolves non-empty, and it then fails inside the caller's own
evaluation with `attribute 'host' missing`. So the guard catches the first shape only.

**Two failures closed, and their root causes are separate.**

1. A den host with `class = "devenv"` fails with `The option 'nixpkgs' does not exist. Definition
   values: - In 'devenv@insecure-predicate/os'`. den always includes its `insecure-predicate` aspect
   through `den.default.includes`, and the aspect injects `${host.class}.imports` with an OS-shaped
   module that sets `config.nixpkgs`. A host whose class is not an OS class then breaks. A bare
   `resolve` never reads `den.default`, so the standalone shells declare no entity at all.
2. `kdn.den.devenv.root` cannot hold a store path. devenv's `claude.code` integration writes
   `files."${devenv.root}/.claude/settings.json"`, which makes the root a **dynamic attribute
   name**, and Nix rejects such a name when it refers to a store path
   (`<devenv>/src/modules/integrations/claude.nix:977`). The option now defaults to `/den-mvp`.

**Pattern V1 fails for the slot route, and it works for every den output.** `flake.nix:250` sets
`nix-configs = self`, so the whole tree hash enters every `modules/universal`-derived derivation and
a new file changes every `drvPath` there. A den evaluation never reads `self`. Measured on
2026-09-10: `denConfigurations.host-darwin` kept the byte-identical `drvPath`
`7zhp7889kchljri5j7phaakfvzv9j3ph-darwin-system-26.11.4cff07d.drv` across a file move, a second host
and a rename. `denDevenvShells.devenv-darwin` kept
`k7iqgp8lv0qk2qp3vqkxii8m4gg8g7v3-devenv-darwin.drv` across a perturbation of an unrelated tracked
file. Removal of the `"${self}"` root extended the gate from `denConfigurations` to all four
outputs.

**The MVP now tests itself, in three tiers.** `checks/den-mvp/tests.nix` holds them, and
`checks/default.nix` merges them into `checks.<system>`. Tier 1 compares evaluated option values.
Tier 2 greps the built nix-darwin toplevel — nix-darwin's own `release.nix` pattern. Tier 3 runs
each devenv shell's `config.test`. **No tier activates anything**, and none needs sudo: tier 2 reads
a store path and never runs it, and tier 3 uses `enterTest`, which devenv keeps separate from
`enterShell`. `nix run '.#checks.aarch64-darwin.den-mvp.smoke'` builds every check and prints one
summary — **11 of 11 pass on 2026-09-10**. The `gh` and `devenv-cli` aspects carry their own
offline assertions, so they travel with the aspect to an external adopter.

`den-eval-routes` turns the hand-measured `drvPath` claim above into a test, so the library route
and the `flakeModule` route cannot drift apart in silence.

One trap the harness found: a den devenv shell must pin `devenv.cli.version`. A null value makes
devenv's `tasks` module prepend `devenv-tasks run devenv:enterTest` to `enterTest`
(`<devenv>/src/modules/tasks.nix:486`), and that binary needs a writable `devenv.dotfile` plus a
task source. A build sandbox gives it neither, so a smoke test fails with `Error: NoSource`.
`config.devenv.latestVersion` is the right value, and it also silences the version-mismatch warning.

**A four-target aspect closes the full-matrix gap.** No slot in this repository targets all four
kinds; the widest is `modules/slots/devenv/`, at three (`nixos`, `darwin`, `home`). So
`modules/den/aspects/devenv-cli.nix` ports that slot and **adds** a `devenv` target the slot has
none of. It is now the only aspect that reaches every den class the harness covers, and
`den-eval-devenv-cli` asserts 12 values across all four.

Reaching the `homeManager` class needed a den **user**, not a home-manager import.
`<den>/modules/aspects/batteries/home-manager.nix` imports
`inputs.home-manager.<class>Modules.home-manager` into the host by itself and forwards each user's
`homeManager` config to `home-manager.users.<userName>`. `checks/den-mvp/users/` holds the one shared
`dev` user. Two traps came out of that work, and neither gives an error:

1. A user's `classes` defaults to `[ "user" ]`, with **no** `homeManager`
   (`<den>/nix/lib/entities/host.nix:157`). A user that omits it silently gets no home-manager
   generation, and the `homeManager` half of every aspect it includes goes nowhere.
2. **den partitions an aspect by scope.** A four-target aspect must be included **twice** on a host:
   once in the host aspect for `nixos`/`darwin`/`devenv`, once in the user aspect for `homeManager`.
   Measured on 2026-09-10: host scope alone gave **0** devenv in
   `home-manager.users.dev.home.packages`; both scopes gave **1**.

`denModules.<aspect>` cannot carry `devenv-cli`. That zero-argument form names one common class per
aspect, and this one has four. `denLib.imports` is the general form, and the test asserts it resolves
one module on each class.

`checks/den-mvp/home/` adds the standalone home-manager route beside the host route. The two answer
different questions. The standalone route asks whether an aspect's `homeManager` half is a valid
home-manager module on its own — the shape an external adopter uses. The host route asks whether den
forwards that half into a real system, and only it can hit trap 2 above.

One test kind stays deferred, for a stated reason. An automated `hosts/anji`-against-`host-darwin`
parity check evaluates a whole personal host (about 93 s) and reads sops metadata. A `runNixOSTest`
VM test is no longer blocked — `host-nixos` carries a real `nixos`-class aspect now — but it still
earns nothing: every value a guest would read is a static option value or a file in the toplevel,
and tier 1 and tier 2 read both. A VM pays off only for a runtime behaviour.

The adopter-facing library-mode export is done. The `home` target and the first `nixos`-class
aspect are both done, through `devenv-cli`.

## Milestone 2 covers every slot — scope decision, 2026-09-10

The user set the target: **reimplement all of `modules/slots/` as den aspects.** A representative
sample is not the goal. The earlier plan named one coupled pair (`jj` plus `mcp`); that pair is now
one step in a full port.

`modules/slots/` holds 18 slots plus a 22-line loader, and 4,160 lines of Nix and shell. **14 den
aspects exist now.** The order table below marks each finished slot **Done**. These three were the
first ports, at the time of the scope decision:

| Slot | LOC | State |
|---|---|---|
| `gh` | 53 | full port — `modules/den/aspects/gh.nix` |
| `devenv` | 61 | full port, plus a `devenv` target the slot has none of — `modules/den/aspects/devenv-cli.nix` |
| `rosetta-builder` | 180 | core options only. The guest-size options stay in the slot. |

**Five slot files remain, at 1,558 lines** (measured 2026-09-10 with `wc -l`). That count reads
`default.nix` files only, and no shell file. The five are `llm` (964), `llm/client` (151),
`llm/proxy` (172), `signing` (196) and `ssh-access` (75). `modules/slots/**/default.nix` holds 19
slot files and 3,392 lines, plus the 22-line loader.

The earlier count named six files at 1,819 lines and left `signing` out. Two corrections apply: the
`jj` pair is ported now, and `signing` belongs on the list. The `LOC` column below keeps the figures
of the scope decision, so a row can differ from a fresh `wc -l`. The `jj` row is the exception: it
carries the measured 457 lines of `default.nix`, where the earlier 949 counted four shell files too.
The order groups the slots by the den mechanism each one needs, and it puts the cheap tests first:

| Order | Slot or family | LOC | Slot targets | What it tests |
|---|---|---|---|---|
| 1 | `ssh-agent` | 76 | `home` | **Done.** The user scope alone. No host target at all. |
| 2 | `ca` | 91 | `nixos` | **Done.** The first `nixos`-only aspect. The option lives inside the `nixos` target. |
| 3 | `nix` | 148 | `devenv` | **Done.** A slot that reads repository content through `${inputs.nix-configs}`. It also sets `kdn.mcp.*`, so it ran **after** the `mcp` family. It needed one new mechanism, `den.devenv.inputs`, because a pre-commit hook needs the `git-hooks` flake input. It also fixes one whole-tree store copy: a run-time wrapper expands `$DEVENV_ROOT`, where the slot froze a read-only store path. |
| 4 | `opencode` | 197 | `devenv` | **Done.** The first de-personalized port: `authKeys`, `settings` and `allowedPaths` replace the provider name and the checkout path that the slot hardcodes. It also fixes one slot defect — a consumer that set `settings` lost the whole permission baseline. |
| 5 | `zellij` | 221 | `devenv` | **Done.** It ships a skill file, two Claude Code hooks and two `packages/` derivations. It needed two new mechanisms: `kdn.isSourceRepo` in `modules/den/common/source-repo.nix`, and a plain `pkgs.callPackage` route to `packages/llm/` with no overlay. |
| 6 | `mcp` family — `mcp`, `snoop`, `pretty-print`, `basic-memory` | 476 | `devenv` | **Done.** Slot-to-slot option coupling, solved with `includes` and no shared declaration file. Two mechanisms measured — see below. |
| 7 | `jj` family — `jj`, `jj/fork` | 457 | `devenv` | **Done.** The second coupled pair, and the largest shell payload. Two aspects, `jj` and `jj-fork`, where `jj-fork` names `jj` in `includes` and `jj` names `mcp`. So one shell now holds four direct includers of one parent and still gets one gateway. It needed no new mechanism. See below. |
| 8 | `llm` family — `llm`, `llm/client`, `llm/proxy` | 1,287 | `nixos`, `devenv` | One family that spans two classes. |
| 9 | `ssh-access` | 251 | `devenv`, `home` | **Blocked on 009.** It carries personal data. |
| 10 | `signing` | 196 | `home` | The `home` target alone, plus a second `home` aspect beside `ssh-agent`. It carries personal data too — a signer principal and a key path. |

### den namespaces land — 2026-09-10, after order 6 and before order 3

**Done.** Every reusable aspect moved from `den.aspects.<name>` to `den.ful.kdn.<name>`. The new file
`modules/den/namespaces.nix` creates two namespaces with `inputs.den.namespace`:

| Namespace | Exported | Holds |
|---|---|---|
| `den.ful.kdn` | yes, as the flake output `flake.denful.kdn` | every reusable aspect |
| `den.ful.personal` | no, never | the creator's own data-carrying aspects. It is empty today. |

**The non-export is the enforcement.** An external adopter cannot name a `personal` aspect at all,
because no flake output carries it. So condition 2 of phase 2 is structural now, not a doc rule.

Five facts, each read from den's own source at the pinned revision:

1. `inputs.den.namespace` is a top-level export of den, with the signature `name: sources: module`.
   It creates the option `den.ful.<name>`, a module-argument alias `<name>`, and — when the second
   argument exports — the output `flake.denful.<name>` of den's own evaluation.
   `modules/den/flake-module.nix` copies that one attribute out to this repository's flake with
   `flake.denful = eval.config.flake.denful;`.
2. **The namespace name is the merge key.** den merges every source's `denful.<name>` into the one
   option `den.ful.<name>`. So two repositories that export the same namespace name **and** the same
   aspect name merge into one aspect: a list option such as `includes` concatenates, and a scalar
   option fails with `defined multiple times`. den's own test `test-multiple-sources-merged` proves
   this is deliberate. There is no export-time alias, so the option path, the module argument and the
   flake output always carry one name. `kdn` is unique enough to make an accidental merge unlikely.
3. **The library route needs two extra modules.** `options.den.ful` and `options.flake.denful` live
   in den's `modules/aspects.nix`, and only `den.flakeModule` loads that file — `den.nixModule` loads
   neither option. So `modules/den/lib.nix` adds that file, plus a small shim that declares
   `options.den.classes`. The shim is needed because den's `namespace.nix` writes `den.classes`, and
   `nixModule` does not declare it. den's own `modules/options.nix` would also work, but it declares
   `den.hosts` and `den.schema` too, and the library route avoids that entity machinery.
4. **den still collapses a diamond `includes` under a namespace.** A probe returned an `imports`
   list of length 1 and one option declaration. So the `mcp` family of order 6 keeps its mechanism.
5. **An entity aspect stays in `den.aspects`.** den finds a host's aspect by the host name and a
   user's aspect by the user name, and it looks in `den.aspects` only. A namespaced aspect reaches an
   entity through `includes` alone. So `checks/den-mvp/host-darwin/default.nix` keeps
   `den.aspects.host-darwin` and includes `kdn.gh`. den's own batteries stay at `den.batteries.*`.

**The conversion found one bug.** `modules/den/classes/devenv.nix` declared its class options under
`kdn.den.devenv.*`. At den level the alias `kdn` is a namespace with a freeform type, so a
declaration under `kdn.<anything>` becomes an **aspect** named `<anything>`. The prefix put a phantom
aspect named `den` into `den.ful.kdn`, and that phantom reached the exported output
`flake.denful.kdn` too. The fix renames the prefix to `den.devenv.*`. After the fix, `den.ful.kdn`
holds exactly the 12 registry aspects and no phantom.

**The general rule the bug produces.** At the top level of an aspect file, `kdn.<name>` names an
**aspect**. Inside a target module, `kdn.<name>` is an **option path** of the consumer's own
configuration. The `kdn.*` option prefix stays reserved for a consumer, inside a target module.

`checks/den-mvp/tests.nix` gained six namespace assertions in the `den-eval-guards` set: the library
route carries the namespace and holds every registry aspect; the namespace holds no aspect outside
the registry; the library route creates no `personal` namespace; the flake route exports the
namespace as one output; the exported namespace holds every registry aspect; and the flake route
never exports `personal`. `den-eval-guards` now passes 11 of 11, and every `aarch64-darwin` den check
builds and passes — **16 of 16**. A system holds 16 den checks: 11 evaluation, 3 artifact and 2
smoke, plus the `den-mvp` build gate. `x86_64-linux` holds 16 too.

The conversion touched `modules/den/namespaces.nix` (new), `modules/den/lib.nix`,
`modules/den/flake-module.nix`, `modules/den/classes/devenv.nix`, all 12 aspect files, all 5 entity
files under `checks/den-mvp/`, and `checks/den-mvp/tests.nix`. Order 3 (`nix`) starts on the
namespaced tree.

### Order 7 — the `jj` pair lands, 2026-09-10

**Done.** Two new files, `modules/den/aspects/jj.nix` and `modules/den/aspects/jj-fork.nix`.
`kdn.jj-fork.includes = [ kdn.jj ]` and `kdn.jj.includes = [ kdn.mcp ]`, so the pair joins the `mcp`
diamond. `checks/den-mvp/devenv/default.nix` lists the leaf `kdn.jj-fork` alone, and both shells
still hold one gateway. The port needed **no new den mechanism**.

Five options carry the data the slot hardcoded. `jj.nix` declares `kdn.jj.upstream.remote` (default
`"origin"`, where the slot named one person's remote), `kdn.jj.upstream.url` and the freeform
`kdn.jj.config`. `jj-fork.nix` declares `kdn.jj.alwaysBlockedMessagePatterns` (default `[ ]`, where
the slot held one real pattern), `kdn.jj.fork.remote`, `kdn.jj.fork.url`,
`kdn.jj.fork.deniedFilePatterns` and `kdn.jj.fork.deniedMessagePatterns`. Every option path stays
exactly as the slot spells it. The rule that splits them: **an option belongs in the aspect that
reads it.**

The port found one real defect, in the slot. `modules/slots/jj/default.nix` sets
`claude.code.agents.jj-expert.proactive`, and devenv removed that option on 2026-08-16
(`<devenv>/src/modules/integrations/claude.nix:367,958`). A definition of it is a hard assertion
failure now. The slot never trips it, because it gates the agent on `kdn.isSourceRepo` and this
repository sets that flag true. `devenv-darwin` sets the flag false, so the den entity surfaced the
latent failure. The aspect drops `proactive` and adds "Use proactively." to the description — the
migration devenv prescribes. **The slot fix needs its own commit.**

The failure also showed a test-tier gap: a failed devenv assertion throws only when something reads
`config.shell` or `config.test`, so a tier-1 evaluation check passes over it. `den-eval-jj` now
asserts an empty failed-assertion list for both shells.

`modules/slots/jj/pre-push.sh:92-95` needed no port fix. The brief named the remote check inverted;
a measurement on 2026-09-10 shows it correct, and `../definition.md` records that P0 as fixed with
15 tests.

Counts, each measured after the port: `den.ful.kdn` holds **14** aspects. A system holds **17** den
checks — 12 evaluation, 3 artifact and 2 smoke — plus the `den-mvp` build gate, so
`nix eval '.#checks.<system>'` lists 18 `den*` names on both `aarch64-darwin` and `x86_64-linux`.
`nix run '.#checks.aarch64-darwin.den-mvp.smoke'` reports **18 passed, 0 failed**. `den-eval-jj`
passes **32 of 32**, and `den-eval-guards` passes 11 of 11.

The port defers every design choice to the user. The creator's instruction of 2026-09-10 says to
mirror the slot and to record each decision instead. The nine `DECISION TO REVISE` lines sit in
`../.worklog.md` under the 2026-09-10 entry.

### Four obstacles the inventory names

Each one is read from the source. Each entry states whether it is solved.

1. **Slot-to-slot option coupling. Solved by order 6.** `modules/slots/mcp/snoop/default.nix:22-23`
   reads `config.kdn.mcp.enable` and writes `kdn.mcp.commandOverlays`. So one slot configures
   another slot's option. The aspect answer is `includes`: `mcp-snoop.includes = [ mcp ]` puts both
   target modules into one evaluation, so the child writes the parent's option directly.

   **Measured on 2026-09-10: den dedupes a diamond.** Three probes. `childA.includes = [ base ]`
   plus `childB.includes = [ base ]` plus `top.includes = [ childA childB ]` gives an `imports`
   list of length 1, and `base` declares its option exactly once. Resolving `base`, `childA` and
   `childB` **separately** and merging all three results dedupes too. den keys each target module
   per aspect, and the module system drops a repeated key — see den's
   `nix/lib/home-env.nix:74`. `den-eval-mcp` asserts the built form: three aspects include `mcp`,
   and the shell holds exactly one gateway package.

   So a shared option needs **no** shared declaration file. It belongs in the aspect that reads
   it, next to that code. `modules/den/common/source-repo.nix` stays a by-path import only because
   `kdn.isSourceRepo` has several unrelated writers.
2. **A slot writes a target option flat.** `modules/slots/mcp/snoop/default.nix:34` sets
   `devenv.packages` with no target wrapper. The slot loader accepts that. den needs the value
   inside a class target, so each such site needs a rewrite.
3. **A flake input can be out of reach. Worked around in order 6.** `mcp-servers-nix` is declared
   in `devenv.yaml` only, never in `flake.nix`, so no den evaluation can reach it. Adding it as a
   flake input would change `flake.lock`, and that would rewrite a pre-checkpoint commit. So the
   aspect takes the source as the option `kdn.mcp.serversNix` (`nullOr raw`, default `null`) and
   the consumer passes it. This is the better adopter shape as well: the adopter passes their own
   source, and a `null` raises a warning that names what stays inert.

   The cost is one test gap: no den check exercises the **real** `mcp-servers-nix`. A stub at
   `checks/den-mvp/mcp-servers-nix-stub/` implements the one function the aspect calls, so the
   translation code is tested on the `stdio`, `args` and `http` branches — but the real server set
   is not.

4. **`ssh-access` holds personal data.** `modules/slots/ssh-access/kdn-graph.nix` carries hosts,
   LAN addresses and zones. It moves to the personal folder of
   [009](../009-personal-data-folder/definition.md) first, so order 9 waits for that checkpoint.

### What needs no new den mechanism

The four-class matrix is proven — `den-eval-devenv-cli` asserts 12 values across `nixos`, `darwin`,
`devenv` and `homeManager`. So orders 1 to 5 need port work only, not den research. Note the name
change: a slot calls the target `home`, and den calls the class `homeManager`.

The README status table tracks each row.

## Why this comes first

If den wins, this repo throws away the work to reimplement modules onto slots. If den loses, the
spike cost is one bounded experiment. So the spike runs before the reimplementation, not after.

den looks less abstract than the alternatives in that space, and a better match to this repo's
problems. That impression needs a test, not agreement.

## Where the spike lives

`modules/den/`, parallel to and independent of `modules/slots/`. Reimplement representative slots
as aspects. **Do not remove or modify `modules/slots/`.**

Pick the representative set deliberately: one devenv-only slot, one that targets `darwin`, one that
targets `home`, and one with cross-slot coupling. `rosetta-builder` is the obvious `darwin` choice.
`jj` couples to `kdn.mcp.*`.

## Success criteria, in order of importance

### Criterion 2 is decisive — test it first

> **Can an external adopter import a resolved den aspect as a plain drop-in module, and not adopt
> den in their own repo?**

This is the whole point. The creator wants an imported drop-in.

What is already known:

- `den.lib.aspects.resolve "<class>" <aspect>` returns a plain module, and it is CI-tested in den's
  own `templates/ci/modules/internal-api/den-as-lib.nix`.
- **But `reference/lib.mdx` labels it "Internal". `guides/debug.md` explicitly warns against
  production use.**
- There is no documented supported route to export aspects as `nixosModules`/`homeModules`. Zero
  doc mentions.
- The repo that produces the aspect must still be a den repo.

So the mechanism exists, and this repo does not trust it. Establish three things. Does it work for
this repo's real cases? Is the Internal label a stability warning or a correctness warning? Will
the maintainers commit to it? den's discussion #569 asks a closely related question, and stays
unanswered since 2026-05-24. Ask there, or open a new question.

**If criterion 2 fails, den does not deliver the goal.** Say so plainly and stop.

**Answered — PASS, with two limits.** See the phase 1 verdict above, and
[research.md](research.md) for the seven cases and the two verified workarounds.

### Criterion 1 — can a `devenv` class exist at all

den has **no** devenv class. Zero mentions in its docs, code, issues, or discussions.
`den.classes` declares only `nixos` and `darwin`; `homeManager`, `hjem`, `maid`, `wsl`,
`flake-parts`, `os`, and `user` come from batteries.

The nearest template, `templates/flake-parts-modules/modules/classes/devshell.nix`, wires
**numtide/devshell, not cachix/devenv**. A devenv class looks like ~15 lines that copy it. But that
rests on one **unverified** point: devenv must be reachable as a flake-parts module or an
`evalModules` target.

13 of 20 slots target devenv. So a failure here is close to fatal.

**Answered — PASS.** devenv is a plain `lib.evalModules` target: `<src>/src/modules/top-level.nix`,
with mandatory `specialArgs.inputs` (it may be `{ }`), `_module.args.pkgs`, `devenv.root`,
`devenv.tmpdir`, and the shell at `config.shell`. It needs no `--impure`, no CLI, and no
CppNix-only builtin. A ~30-line `den.classes.devenv` produced real derivation paths on three
routes, and den's own `policy.instantiate` route gives a bit-identical `drvPath` on `main` and on
v0.18.0. `SPIKE_HOST=igloo` proved entity data reaches a devenv aspect.

**Correction to the sketch above:** copy `templates/terranix-demo/modules/terranix.nix`, which uses
`policy.instantiate`. Do not copy `devshell.nix` — devenv is a separate `evalModules` universe, not
a flake-parts module.

### Criterion 3 — does den satisfy the conditional-imports requirement

Checkpoint 005 writes that requirement down as a testable statement. Test den against it here.

Known constraint: den's resolution runs **before** `evalModules`, with function-argument-shape
introspection plus `nix-effects`. That solves imports that depend on entity or context **data**. It
does not obviously solve imports that depend on module **config**. Establish which kind this repo's
requirement needs — 005 answers that.

### Criterion 4 — does the 1→N mixed-aspect collision still reproduce

A third-party evaluation against about v0.15 documented one collision. A mixed aspect holds both
`nixos` and `homeManager` keys. On a host with two users, it defines the host-level config twice:

```
The option 'boot.kernelPackages' is defined multiple times
```

The documented workaround splits every mixed aspect into host and user halves. The author says that
defeats the point of aspect-oriented configuration. den's PR #609 fixed a related leak. v0.16
through v0.18 changed `entity.aspect` semantics, so this may be stale. **Re-test on current den.**

**Answered — REFUTED.** `boot.kernelPackages` resolves to one value on both revisions, with one
mixed aspect included by two `homeManager` users. The collision message stays reachable for a
genuine two-aspect conflict, and it now carries useful `nixos@<aspect>` labels. One side finding to
keep: a **host**-scope mixed aspect's `homeManager` half never reaches
`home-manager.users.<user>`. That is den's scope partitioning, and `den.batteries.forward` is the
bridge.

## Risks to record in the outcome

- den is v0.x with **no stable API**. v0.16 changed `entity.aspect` semantics. v0.18 scoped the
  entity-arg binding. Both are breaks. Wholesale renames: `den.ctx` → `den.schema`,
  `den.provides`/`den._` → `den.batteries`, `meta.adapter` → `meta.handleWith`. There is a whole
  `lib-deprecated.mdx` page. No patch release has ever shipped.
- `main` carries about 2.5 months of unreleased drift past v0.18.0 (2026-06-23).
- 31 contributors, but **2 people are about 90% of commits**.
- The core rests on `denful/nix-effects` — 2 stars, single author — despite "zero dependencies"
  marketing.
- den needs neither flakes nor flake-parts. `templates/noflake` uses npins plus `lib.evalModules`.
  `den.nixModule` works in any `evalModules`. That is genuinely good for this repo.

## Kill criterion

Stop and record a negative outcome if **criterion 2 fails**, or if you cannot meet **criterion 1**.

State the central tension in the outcome either way:

> den's strongest claim would improve the creator's own ergonomics. That is not the same as support
> for external adoption. Only criterion 2 decides the second question.

## Deliverable

A `.done.md` sibling with a verdict per criterion. Tag each verdict confirmed or unverified, with
the evidence. Then feed it into 006.

Note that 003's plain-import boundary is framework-agnostic. Whichever way this goes, an adopter's
entry point should not require them to learn the creator's framework choice.
