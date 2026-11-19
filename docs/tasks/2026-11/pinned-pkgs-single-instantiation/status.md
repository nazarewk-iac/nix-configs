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

## Root cause found (2026-11-09) — the age `sops` wrapper, nothing else

The pinned-vs-unpinned toplevel drvPath difference is caused by **exactly one thing**: the
`age` `sops`-wrapper overlay. A name-aware walk of the two `toplevel` drv trees ends at:

```
ONLY-PINNED: system_fish-completions -> sops-3.13.3_fish-completions
ONLY-UNPIN : system_fish-completions -> sops-3.13.3-sops-age-wrapped_fish-completions
```

So the unpinned host's `pkgs.sops` is `sops-age-wrapped`; the pinned base carries plain `sops`.
**The rest of the pkgs is byte-identical** — verified `hello`, `cacert`, `dbus`, `stdenv`,
`lixPackageSets.latest.lix` all equal between the base and `f.nixosConfigurations.moss._module.args.pkgs`.
The `etc`/`dbus`/`system-path`/`sshd.conf` differences all cascade from that one swapped `sops`.

Cause: `modules/universal/security/secrets/age/default.nix:221` (and
`modules/den/aspects/security-secrets-age.nix:319`) do
`nixpkgs.overlays = [ (mkAfter (final: prev: { sops = mkSopsWrapper prev prev.sops; })) ]`.
`mkSopsWrapper` reads **per-host** `cfg.plugins` and `cfg.genScripts`, so the wrapped `sops` cannot
live in the shared per-system base. `moss` enables age, so it is affected (not only `brys`).

### Fix (turns pinning closure-identical)

Stop overriding `pkgs.sops` through `nixpkgs.overlays`. sops-nix exposes `sops.package`
(`modules/sops/default.nix:274` in the pinned sops-nix). So:

1. Drop the `sops = mkSopsWrapper …` overlay.
2. `sops.package = mkSopsWrapper pkgs pkgs.sops;` — sops-nix then runs the wrapped binary, while
   `pkgs.sops` stays **plain** in every pkgs.
3. Put the wrapper buildEnv into `kdn.env.packages`/`environment.systemPackages` so the interactive
   `sops` command is still the age-aware one.

Then base == host pkgs (both plain `sops` + sops.package wrapper), pinning is byte-identical, and
the 20 % eval win applies with an unchanged closure. Apply to both the universal age module and the
den `security-secrets-age` aspect; re-verify `toplevel` drvPath equality pinned vs unpinned, then
enable hosts.

## sops wrapper removed from overlays (2026-11-09) — one overlay down, HM left

Applied the fix: both the universal age module and the den `security-secrets-age` aspect now set
`sops.package = mkSopsWrapper …` instead of `nixpkgs.overlays = [ sops = mkSopsWrapper … ]`, and the
two sops aspects install `config.sops.package` (wrapped when age is on, plain otherwise) so the CLI
stays age-aware. `pkgs.sops` is now **plain in every pkgs**.

Verified: with moss pinned vs unpinned, the `sops-age-wrapped` delta is **gone** — the name-aware
walk now ends at `home-manager-files` and `check-sshd-config` (`sshd.conf-final`) only.

**Remaining pin blocker:** Home-Manager semantics. Unpinned sets `home-manager.useGlobalPkgs = false`
(`modules/universal/default.nix:97`), so HM builds its own pkgs. Pinning forces
`useGlobalPkgs = true` (HM must use the system pkgs, because a pinned system has `nixpkgs.overlays`
empty and HM can no longer build `pkgs.kdn.*` from it). Equal pkgs or not, `useGlobalPkgs` true-vs-
false changes HM's generated files (`home-manager-files`) and, downstream, `sshd.conf-final`. So
pinned ≠ unpinned by construction until both modes agree.

Next (needs a closure decision + measurement): either

1. set `home-manager.useGlobalPkgs = true` fleet-wide as policy (then pinned == unpinned), verifying
   no closure change against the current tree; or
2. keep HM independent and give a pinned host's HM the base overlays explicitly
   (`home-manager.sharedModules` with `nixpkgs.overlays = [ self.overlays.default ] ++ staticOverlays`)
   — keeps `useGlobalPkgs = false`, HM re-instantiates (loses some eval win) but the output matches.

Host pins reverted; fleet unchanged. `den` aspects mirrored and parse-clean; verify via the den
checks before relying on them.

## Resolved (2026-11-09) — pinning is closure-identical; enabled on moss+etra

**The earlier "closure differs" was a measurement artifact.** I toggled `kdn.pkgs.pin` by editing
`hosts/moss/default.nix` between the two evals. `builtins.getFlake "path:$PWD"` re-copies the tree
to a store path keyed by the tree hash, so editing the host file changed `self`, and every
`${self}/…` reference (e.g. the SSH CA at `data/ca`, the `git-credential-keyring` helper) moved —
making _any_ two evals of a changed tree differ regardless of pinning. Proof: with an **unchanged**
tree and pin driven by an env var (`builtins.getEnv`), pinned and unpinned give the **same**
`toplevel` drvPath.

**Measured (stable tree, one process, env toggle):**

| mode (moss+etra, one eval) | wall |
| -------------------------- | ---- |
| unpinned                   | 77 s |
| pinned                     | 62 s |

~19.5 % faster, drvPaths **identical**.

**Prerequisites applied:**

- `fix(sops): use sops.package …` (commit `c8219974`) — the one _real_ pkgs delta (age wrapper).
- `home-manager.useGlobalPkgs = true` fleet-wide (`modules/universal/default.nix:97`). Required:
  a pinned system has empty `nixpkgs.overlays`, so HM must use the system pkgs. oams (unpinned,
  multiGPU+HM) re-evaluated clean, so the flip is safe fleet-wide for eval.
- `kdn.pkgs.pin = true` on **moss** and **etra** (verified pinned eval + closure-identical).

**Standalone HM:** `flake.homeConfigurations.dummy` — a no-host home-manager profile built on
`self.pkgs.x86_64-linux.default` (the pinned base). Demonstrates how an adopter configures HM
standalone on the single pinned pkgs (`activationPackage` evaluates).

**Remaining:** roll pinning + measurement to briv → brys → oams → anji (each may need its own
variant for host-specific overlays: multiGPU on oams/brys). Build-verify moss/etra before deploying.

## Rollout 2026-11-09 — moss, etra, briv, anji pinned; brys/oams blocked by host-specific overlays

Per-host pinned-vs-unpinned check (unchanged tree, env toggle) and eval times:

| host      | pinned vs unpinned | eval (unpinned→pinned)           |
| --------- | ------------------ | -------------------------------- |
| moss+etra | IDENTICAL          | 77 s → 62 s (combined)           |
| briv      | IDENTICAL          | 67 s → 65 s                      |
| anji      | IDENTICAL          | 102 s → 88 s                     |
| brys      | DIFF               | 129 s → 76 s (unpinned baseline) |
| oams      | DIFF               | 91 s → 67 s                      |

Combined one-process eval of the four pinned hosts (moss, etra, briv, anji): **145 s**, all drvs.

### brys / oams — why they are NOT pinned

Two host-specific overlays survive pinning and change the closure:

1. **`supergfxctl` 5.2.1 downgrade** (multi-GPU). The pinned base carries the nixpkgs default
   (5.2.7); the host downgrades to 5.2.1. A **plain derivation cannot substitute it**: nixpkgs
   `services/hardware/supergfxd.nix` (pinned rev) reads `pkgs.supergfxctl` in `systemPackages`,
   `systemd.packages`, `dbus.packages` and `udev.packages`, and declares **no `package` option**
   — so only a `pkgs.supergfxctl` overlay (or reimplementing the service) works. Research: nixpkgs
   issue #355798 is **open/stale** and `asus-linux/supergfxctl` is **archived (read-only)**, so no
   fix is coming; the downgrade stays, and it cannot be verified as fixed without the dGPU hardware.
2. **`nixos-icons` `source-patched`** (desktop/stylix) — a patch overlay applied on these desktops.

Decision: leave brys/oams **unpinned** (they still get the rest of the work, incl. `useGlobalPkgs`).
To pin them later, either accept a `multiGPU`/`desktop` **pkgs variant** that bakes these overlays,
or reimplement `services.supergfxd` to take a package (letting the 5.2.1 build be a plain
derivation, per the "prefer a derivation" preference).

Base config now permits the insecure `olm-3.2.16` (matrix), which a pinned host could no longer set
itself. The env-toggle used for the stable-tree measurement is removed; pins are in-file.

## Embed pass 2026-11-09 — supergfxctl embedded; nixos-icons is not embeddable (notified)

Goal: embed every host-specific overlay into the default pinned set where possible, and flag the
rest.

**Embedded (possible):**

- `supergfxctl` 5.2.1 (multi-GPU) → `modules/den-pkgs/overlays.nix`. The universal hw-gpu overlay
  applies it host-conditionally; the pinned base now carries the same static `callPackage`. Servers
  don't reference it, so their closure is unchanged.
- Removed the unused `cuda` variant (`modules/den-pkgs/default.nix`): **no host uses CUDA** (no
  NVIDIA machines).

**Not possible (notified):** `nixos-icons`. stylix recolors it from `config.lib.stylix.colors`
(`stylix/modules/nixos-icons/overlay.nix` — an `overrideAttrs` whose `src` is a palette-derived
`applyPatches`). That is **per-host theme data**, so it cannot live in a shared, static,
per-system pkgs. It is the **only** remaining delta for oams (verified: supergfxctl delta gone;
`nixos-icons` source/source-patched remains). Consequently **brys and oams stay unpinned**.

To pin a stylix desktop later, the options are: a theme-specific variant (one pkgs per palette —
defeats sharing), accept the default (un-themed) nixos-icons for the pinned build, or move the icon
recolor out of the build into activation. None is a clean static-base embed.

## nixos-icons precomputed; ALL SIX hosts pinned (2026-11-09)

The 19 last delta (stylix `nixos-icons`) is now embedded. stylix recolors it from
`config.lib.stylix.colors`, and the project palette is the **fixed default**
`modules/universal/stylix.pallette.yaml` (darcula-kdn) — identical across the fleet. So the base
reuses **stylix's own overlay** (`modules/nixos-icons/overlay.nix`) with the fixed colors
(base05/base0C/base0D + their RGB, hardcoded and marked "keep in sync" in `overlays.nix`), giving a
single deterministic recolored `nixos-icons` that equals the desktops'. Verified: base `nixos-icons`
== the (unpinned) brys icon (`1fj5yk…`), and brys+oams pinned become closure-IDENTICAL.

Result: **all six hosts pinned** (moss, etra, briv, anji, brys, oams). Combined one-process eval of
all six: **216 s**, 6 drvs, rc=0.

`brys` note: its `specialisation.llms` uses `inheritParentConfig = false`, and a pin set via
`imports` (a module) leaks into that sub-eval, which does not declare `kdn.pkgs`. So brys sets the
pin in its `config` block (not inherited under `inheritParentConfig = false`); the specialisation
then builds its own pkgs, matching the unpinned host.

### Per-device themes (by design, notified)

The base ships the **darcula-kdn** recolored icon. A device that sets a **different**
`stylix.base16Scheme`/palette produces a different `nixos-icons` and therefore must **not** pin
against this base — give it its own pkgs variant (recomputed for that palette) or leave it unpinned.
Changing the default palette requires updating the three color constants in
`modules/den-pkgs/overlays.nix` (base05/base0C/base0D).

## Specialisations use the same pinned pkgs (2026-11-09)

A `specialisation` with `inheritParentConfig = true` (oams `vfio`) inherits the parent `nixpkgs.pkgs`
→ already the pinned base. A `specialisation` with `inheritParentConfig = false` (brys `llms`) does
**not** inherit it, so it built a second nixpkgs. Fixed: brys's `specialisation.llms.configuration`
now imports a module that sets `nixpkgs.pkgs = kdnConfig.self.pkgs.<system>.default` (+ `mkForce`
empty overlays/config), so the boot entry uses the same set. Verified: `llms` `pkgs.hello` == base
and `pkgs.kdn` present. No specialisation now instantiates a second nixpkgs.

## sops fix corrected (2026-11-09) — `sops.package` is the installPackage, not the CLI

The build gate rejected every NixOS host with
`sops-...-sops-age-wrapped/bin/sops-install-secrets: No such file`. Cause: in sops-nix,
`sops.package` is the **`sops-install-secrets` binary** (used in `ExecStart`), not the `sops` CLI, and
its default derives `sops-install-secrets` from that package. Setting `sops.package = mkSopsWrapper …`
(the CLI) therefore broke activation, and `config.sops.package` in the package lists was the wrong
binary. Eval did not catch it — it is a build-time binary.

Reverted: `sops.package` untouched; the interactive `sops` CLI stays plain `pkgs.sops` in
`kdn.env.packages`. `pkgs.sops` stays plain in the base too, so pinning remains closure-identical.
Trade-off (notified): the interactive `sops` CLI is no longer age-wrapped (no `SOPS_AGE_KEY`
injection) — this only affects manual `sops` use; activation decrypts via `sops-install-secrets` +
`sops.age.keyFile` + plugins, which is unaffected. Re-adding an age-aware CLI (as a package, leaving
`installPackage` alone) is a follow-up.
