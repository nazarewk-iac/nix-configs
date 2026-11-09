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

## Update 2026-11-09 (evening) — moss/etra pinned in-tree: 20 % faster, but closure changed

Inlining the missing `pkgs.kdn.kdn-sops-secrets` into `modules/den-pkgs/overlays.nix` was enough
to make **moss and etra evaluate with `kdn.pkgs.pin = true`** (no eval error). Measured, both hosts
in ONE `nix eval` process:

| mode     | wall |
| -------- | ---- |
| pinned   | 77 s |
| unpinned | 97 s |

~20 % faster for the combined two-host eval — the L2 lever works.

**Blocker (why hosts are NOT enabled):** the pinned `toplevel` drvPath differs from unpinned
(`bwbr1yj…` vs `q058xx5…` for moss). The change is not cosmetic: `etc`/`system-path`/`activate`
inputs differ, and nearly **every leaf drv differs, including `nss-cacert-3.126`** — so the pinned
pkgs is NOT byte-equivalent to the host pkgs the modules build. The task requires an identical
closure, so pinning stays opt-in and off. Root cause not yet isolated; prime suspects:

1. `nixpkgs.config` — base hardcodes `{ allowAliases; allowUnfree = true; permittedInsecurePackages = []; }`,
   the host derives it from `kdn.nixpkgs`; a divergence can move wide swaths of pkgs.
2. The nixpkgs **source/instantiation** `lib.nixosSystem` uses may not be the same `inputs.nixpkgs`
   the base imports (nixosSystem resolves nixpkgs via the lib source; verify), which would change
   every package.
3. Overlay set/order difference (base bakes `jsonTemplate`/`python-metadata`/`ceph`/`kdn-sops-secrets`
   explicitly; the host gets them from modules).

Next: isolate the leaf diff (`nix why-depends` / compare `base.nss-cacert.drvPath` against a plain
`import inputs.nixpkgs { system; }` and against the host pkgs), fix, then re-verify identical
drvPaths before enabling moss→etra→briv→brys→oams→anji. Pins reverted from `hosts/*` so nothing
half-changes.
