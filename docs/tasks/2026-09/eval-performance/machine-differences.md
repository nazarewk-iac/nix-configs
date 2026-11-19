---
type: Reference
description: Why host evaluation times differ across machines in this repo — measured eval-only baselines and a ranked set of causes, with the pkgs-pinning task as one lever. Companion to research.md/design.md.
timestamp: 2026-11-09T11:00:00+01:00
---

# Machine-to-machine evaluation-time differences

This note estimates **why one host evaluates much slower than another**. It does not replace
[research.md](research.md) (where the time goes inside one eval). It explains the _spread_ across
hosts, and it names the levers. The [pinned-pkgs task](../../2026-11/pinned-pkgs-single-instantiation/definition.md)
is lever 2 below.

## Measured eval-only baselines (2026-11-09)

`config.system.build.toplevel.drvPath`, one cold `nix eval` process per host, `--option builders ""`
(no build, no IFD), from the repo working tree:

| host | system         | eval-only | weight class                      |
| ---- | -------------- | --------- | --------------------------------- |
| moss | x86_64-linux   | 70.5 s    | headless server                   |
| etra | x86_64-linux   | 82.0 s    | server + LLM gateway              |
| briv | aarch64-linux  | 84.2 s    | Pi-class server                   |
| brys | x86_64-linux   | 239.7 s   | x86 + 4 boot specialisations      |
| oams | x86_64-linux   | 147.9 s   | desktop + specialisation.vfio     |
| anji | aarch64-darwin | 241.7 s   | macOS desktop + devenv + homebrew |

**Methodology caveat (important).** These numbers use `builtins.getFlake "path:…"`, which re-copies
the tree into the store on every run and starts a fresh eval with no warm eval cache. They are
inflated against the **warm** figure in [definition.md](definition.md) (anji warm = 64 s in
2026-09). The _relative_ spread is the useful signal; absolute values move with warm/cold and with
`path:` copying. Re-measure warm before quoting absolute numbers.

## Ranked causes of the spread (estimate, to be confirmed per host)

1. **Boot specialisations are whole extra NixOS configurations.** `config.system.build.toplevel`
   contains every `specialisation.*` sub-config, each fully evaluated. `brys` has four appliance
   specialisations (`hosts/brys/llm-appliance.nix`, `llms-frontier.nix`, …) → brys is the slowest
   x86 host (240 s). `oams` has one (`specialisation.vfio`, `hosts/oams/default.nix:405`). This is
   the **single biggest** differentiator and it is _independent_ of nixpkgs instantiation: the
   module graph is evaluated N+1 times.
2. **Repeated nixpkgs instantiation + overlays per host.** Each `nixosSystem`/`darwinSystem`
   `import inputs.nixpkgs { overlays = [ self.overlays.default ] … }` afresh, and several aspects
   add more `nixpkgs.overlays` host-conditionally (`modules/universal/default.nix:136,170`, sops
   `jsonTemplate`, age `sops`-wrapper, keepass, openvpn, hw-gpu multiGPU). `reflex`/fixpoint
   evaluation of nixpkgs is repeated per host. This is exactly what the
   [pinned-pkgs task](../../2026-11/pinned-pkgs-single-instantiation/definition.md) removes: one
   `pkgs` value per `(system, variant)`, shared by every host of that system inside one eval
   process. In a single-process multi-host eval this is the compounding win: an all-six eval took
   ~90 s total versus ~590 s summed, most of it the shared nixpkgs work.
3. **Desktop/profile module weight.** oams and anji are desktops (sway/dconf/waybar/nwg-shell,
   many home-manager modules and users); moss/etra/briv are servers with a handful of modules. The
   den/universal module graph and HM user configs dominate oams/anji's extra time beyond servers.
4. **darwin-only evaluators.** anji (aarch64-darwin) pays for nix-homebrew/nixcasks/homebrew
   evaluation and darwin HM, on top of the module graph. anji is ~1.5–3× the Linux servers even
   though it has fewer NixOS-style modules.
5. **devenv overlay on the host `pkgs`.** orr/anji/oams/brys wire devenv; the devenv overlay pulls a
   second patched nixpkgs into the host eval (research.md: devenv-patched nixpkgs = 17.1 % of
   function calls). A host without devenv (moss/etra/briv) avoids it. This is the design.md lever
   "remove the devenv overlay from a host pkgs".
6. **Age `sops`-wrapper overlay is host-config-dependent** (`modules/universal/security/secrets/age/default.nix`
   reads `cfg.plugins`/`cfg.genScripts`). Only `brys` enables age; this is why brys cannot share a
   static per-system pkgs without first moving the wrapper out of `nixpkgs.overlays`.
7. **Store round-trips / input refetch (wall≫CPU).** definition.md: wall ≈ 2× CPU on a warm run.
   Uniform across hosts, but `path:` copying inflates this for every host in the table above.

## Levers, ranked by value per unit of risk

- **L1 (biggest, orthogonal to pinning): reduce/scoped boot specialisations.** Each specialisation
  is a full config eval. Harvesting by making a specialisation share a parent config
  (`inheritParentConfig`), or accepting fewer, dominates. Needs a closure proof (specialisations
  are part of output).
- **L2: one pinned `pkgs` per `(system, variant)`** — the pkgs-pinning task. Collapses the repeated
  nixpkgs instantiation across hosts of the same system. Best measured in **one multi-host eval**
  (the compounding case). Blocked for age-wrap / multiGPU hosts until those overlays are extracted
  or guarded; the static, prev-only overlays (`jsonTemplate`, keepass, openvpn, the python-ext
  cython fix) are safe to bake into one base.
- **L3: drop the devenv overlay from host `pkgs`** (design.md, ~17 %).
- **L4: warm-cache + `GC_INITIAL_HEAP_SIZE` + no `path:` copy** in the measurement path — reduces
  the wall≫CPU gap without changing any output.

## How this connects to the pkgs-pinning task

The pinned-pkgs work is **L2** here. It is not the top lever (L1 is), but it is the one that makes
the _fleet-wide_ eval (all hosts at once) cheap, because it lets every host of a system reference
one already-evaluated `pkgs`. This note's per-host table is the baseline L2 should be measured
against; the acceptance is a drop in the **combined one-process** eval of the hosts it pins.
