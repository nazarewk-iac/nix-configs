---
type: Status
description: The isolated pkgs producer and the opt-in pin module have landed; no host is pinned yet because enabling a host first requires inlining every module-provided pkgs.kdn.* overlay into the base.
task: definition.md
authored_by: agent
timestamp: 2026-11-09T12:00:00+01:00
---

# Pinned-pkgs — status

## Landed (commit `fe58f9f9`)

- `modules/den-pkgs/` — an **isolated** root (deliberately not the den tree) that produces
  `<flake>.pkgs.<system>.{default,cuda}`. Each variant is one `import inputs.nixpkgs` with
  `self.overlays.default` plus the **static, host-independent** overlays baked in:
  - `jsonTemplate` (was inline in the sops module),
  - the `pythonMetadataCheck` fix (`cython_0`) and the `ceph` python-metadata override (were inline
    in `modules/universal/default.nix`).
  Verified for `x86_64-linux`, `aarch64-linux`, `aarch64-darwin` (`hello` resolves on each; `cuda`
  variant present).
- `modules/den-pkgs/pin-module.nix` — opt-in `kdn.pkgs.{pin,variant}`. When pinned:
  `nixpkgs.pkgs = self.pkgs.<system>.<variant>`, `nixpkgs.overlays`/`nixpkgs.config` `mkForce`d
  empty (mutually exclusive with `pkgs`), and `home-manager.{useGlobalPkgs,useUserPackages}` forced
  on so users ride the same pinned pkgs.
- `modules/universal/_hm-bootstrap.nix` — skips HM `nixpkgs.*` when
  `home-manager.useGlobalPkgs` is on (otherwise home-manager trips its "nixpkgs options are
  disabled when useGlobalPkgs is enabled" assertion).

**No host is pinned.** Unpinned hosts eval unchanged (moss/etra/anji re-verified after landing).

## Why host enablement is blocked (the remaining work)

Enabling `kdn.pkgs.pin = true` on `moss` reaches, in order:

1. `pkgs.kdn.git-utils` — OK, supplied by the `./packages` overlay in `overlays.default`.
2. `pkgs.kdn.kdn-sops-secrets`, and by extension the other `pkgs.kdn.*` commands — **missing**: the
   universal `security/secrets/sops` module builds `kdn-sops-secrets` inside its own
   `nixpkgs.overlays`, not in `./packages`. Any module that adds a `pkgs.kdn.*` via
   `nixpkgs.overlays` breaks a pinned host, because the pinned base does not carry that overlay.
3. The HM `useGlobalPkgs` assertion (fixed here) and the general "leftover overlay silently
   appended to `nixpkgs.pkgs`" risk from [design-den-root.md](design-den-root.md) § D.

So the next chunk is the **overlay-inlining audit**: move every module-provided `pkgs.kdn.*` (and
any other package a pinned host's modules reference by overlay) into `./packages` (or
`modules/den-pkgs/overlays.nix`), then guard the module `nixpkgs.overlays` off when pinned. Only
then enable `kdn.pkgs.pin` host-by-host (moss → etra → briv → brys → oams → anji), measuring
eval-only each time.

## Blocker for the non-static overlays

- `age` sops-wrapper overlay is **host-config-dependent** (`cfg.plugins`/`cfg.genScripts`, only
  `brys` enables age) — cannot be shared. Move it to a `lib.hiPrio` package in
  `environment.systemPackages` (design § D) before brys can pin.
- `hw-gpu` multiGPU package override (`oams`, `brys`, `pryll`) is host-provided — needs its own
  variant or stays unpinned.

## Measurement

Baselines (eval-only, cold process) are in
[../../2026-09/eval-performance/machine-differences.md](../../2026-09/eval-performance/machine-differences.md).
The acceptance for L2 is a drop in the **single-process multi-host eval** once hosts share one
`pkgs`. Not measured yet (no host pinned).
