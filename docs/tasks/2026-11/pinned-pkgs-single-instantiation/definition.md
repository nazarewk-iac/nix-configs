---
type: Task
description: Instantiate nixpkgs exactly once per supported system (arch+OS) at the flake level, with every repo overlay pre-applied ("inlined"), and force that one pkgs value down into every target (nixos/darwin, home-manager, devenv, colmena) while forbidding new overlays or re-instantiation — to cut evaluation cost.
status: open
authored_by: agent
timestamp: 2026-11-08T18:06:09+01:00
---

# One pinned `pkgs` per system, forced down into all targets

## Context

`nix` does not memoize `import inputs.nixpkgs { … }`: every call is a fresh
instantiation. The repo instantiates nixpkgs many times:

- `flake.nix:466` (`meta.nixpkgs` for colmena) and `flake.nix:481`
  (`meta.nodeNixpkgs."<host>"`, one `import inputs.nixpkgs` **per host**),
- `flake.nix:511` (easykubenix),
- each `nixosSystem` / `darwinSystem` (per host) and every `devenv` /
  home-manager evaluation,
- each applying `overlays = [ self.overlays.default ]` again.

`self.overlays.default` (`flake.nix:238`) is a `composeManyExtensions` over the
repo packages overlay plus `nur`, `microvm`, `angrr`, `nix-darwin`, `devenv`,
`oh-my-pi`. Applying it N times and instantiating nixpkgs N times is the cost.

Goal: **one `pkgs` value per `system`** (arch+OS), computed once, referenced
by every target; overlays baked in; adding an overlay or re-instantiating is
made impossible or loudly rejected. Related: [../2026-09/eval-performance/](../2026-09/eval-performance/definition.md)
(profiling; this is one concrete lever) and [../2026-09/generalization/](../2026-09/generalization/definition.md)
(adopter reuse).

## Design sketch

1. **One instantiation at the flake.** Build, once, per supported system:

   ```nix
   pkgsFor = system: import inputs.nixpkgs {
     inherit system;
     overlays = [ self.overlays.default ];   # everything inlined here
     config = sharedNixpkgsConfig;           # uniform per system (see constraints)
   };
   pinnedPkgs = lib.genAttrs supportedSystems pkgsFor;
   ```

   Expose it as a flake output (`self.pinnedPkgs` / `legacyPackages`) and via
   `kdnConfig` so den aspects and `specialArgs` reach the same value.

2. **Force it into every target** (pass the value, never re-import):
   - **nixos/darwin**: set `nixpkgs.pkgs = pinnedPkgs.${system}` in a module
     (kills the per-host `nixosSystem` instantiation). `nixpkgs.pkgs` is
     mutually exclusive with `nixpkgs.overlays`/`nixpkgs.config`/`hostPlatform`,
     so those must be cleared/derived from the pinned pkgs.
   - **home-manager**: `nixpkgs.pkgs = pinnedPkgs.${system}` (this repo has no
     standalone HM module yet; add the wiring so an HM-only consumer can use it).
   - **devenv**: point devenv's `pkgs` at `pinnedPkgs.${system}`.
   - **colmena / easykubenix**: replace the per-node `import` with the single
     value (biggest immediate win — `nodeNixpkgs` is one import per host).

3. **A `pinned-pkgs` den aspect** (the enforcement point, classes
   `nixos`/`darwin`/`homeManager`/`devenv`):
   - `nixpkgs.pkgs = lib.mkDefault pinnedPkgs.${system}` (or `mkForce`),
   - `nixpkgs.overlays = lib.mkForce [ ]` and a fixed `nixpkgs.config`,
   - **reject re-instantiation**: an assertion/`throw` when a consumer sets a
     non-empty `nixpkgs.overlays`, or `nixpkgs.config` diverges from the pinned
     config, or `nixpkgs.pkgs != pinnedPkgs.${system}`; `lib.warn`/`abort` with a
     clear message ("overlays are inlined into the shared pkgs; add to
     `self.overlays.default` instead").

4. **Overlay inlining audit.** Every `pkgs.kdn.*` / third-party package the repo
   uses must originate from `overlays.default` (it does today). Document that
   adding a package means extending the single overlay set, never a per-host
   `nixpkgs.overlays`.

## Constraints and trade-offs (must be decided in this task)

- **`nixpkgs.config` can no longer vary per host.** `allowUnfree`, `cudaSupport`,
  `permittedInsecurePackages`, etc. currently may differ per host; a single
  instantiation forces one config per `system`. Inventory every
  `nixpkgs.config` in the repo, unify where possible, and record any host that
  genuinely needs a divergent config — the escape hatch is either a second
  deliberately-instanced pkgs (documented cost) or dropping that need.
- **`hostPlatform` is fixed by the shared pkgs.** Cross-compilation
  (rosetta-builder images, `aarch64`/`x86_64` special cases) must come from the
  matching `pinnedPkgs.<system>`, not a locally-`extend`ed set. (See the
  `aarch64-darwin` busybox/hostPlatform note at `flake.nix:668`.)
- **nix-darwin / HM**: `nixpkgs.pkgs` conflicts with `nixpkgs.hostPlatform`;
  set exactly one. Verify nix-darwin accepts `nixpkgs.pkgs` on its pinned
  revision.
- **devenv** derives its own pkgs; confirm the option to pin it and that
  `pkgs.kdn.*`/`pkgs.omp`/etc. survive (i.e. devenv sees the overlaid set).
- **flake `checks`/`packages`** use `legacyPackages`; route them through
  `pinnedPkgs` too, or accept a documented second instantiation.
- **den specialArgs** currently carry `system` + `kdnConfig`; add the pinned pkgs
  (or a per-system accessor) so aspects never call `import inputs.nixpkgs`.

## Verification

- Use the `eval-performance` harness (`hack/eval-profile.sh`,
  `hack/eval-compare.sh`, `checks/README.md` commands) to measure `den-eval-n`
  before/after. Target: a measurable drop, and **zero** further
  `import inputs.nixpkgs` calls outside the one `pkgsFor`.
- Count instantiations: `nix eval --trace-function-calls` (grep the nixpkgs
  `import`) or an eval-gc trace; assert a single instantiation per system.
- Negative test: a throwaway module that sets `nixpkgs.overlays = [ … ]` (or a
  divergent `nixpkgs.config`) fails evaluation with the new message.
- Closure sanity: a couple of hosts still build (`nix build` a toplevel) and
  `devenv` still enters, proving the pinned pkgs is complete.

## Acceptance criteria

- Exactly one nixpkgs instantiation per supported `system`; no per-node/per-host
  `import inputs.nixpkgs`.
- All hosts, HM, devenv evaluate with the pinned pkgs; `den-eval-n` improves
  versus the recorded baseline.
- Adding an overlay (or a divergent `nixpkgs.config`/`hostPlatform`) is rejected
  with an explicit, actionable error; the "add to `self.overlays.default`"
  path works.
- The `nixpkgs.config` unification is documented, with the list of any
  exceptions and why.

## Open questions

- Does nix-darwin on the pinned revision support `nixpkgs.pkgs` fully (vs.
  `nixpkgs.hostPlatform`)?
- How does `devenv` behave when handed an externally-instantiated `pkgs`
  (its `devenv.*` options, `pkgs.omp`)?
- Is one `pkgs` per `system` enough, or do we need per-`config` variants for a
  couple of hosts (e.g. CUDA)? Measure the eval cost of a second variant vs its
  value.
- Interaction with `nixpkgs.legacyPackages` consumers (colmena, easykubenix,
  `nix flake check`) — route through `pinnedPkgs` or document.
