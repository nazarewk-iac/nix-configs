# Rosetta-backed multi-arch Linux builder darwin slot.
#
# Enables cpick/nix-rosetta-builder on an aarch64-darwin host so it builds both aarch64-linux
# and x86_64-linux locally. x86_64-linux runs under Rosetta 2 (near-native) instead of QEMU-TCG
# emulation. This is the first slot that targets the `darwin` slot target; all earlier slots
# target `devenv` only.
#
# The bootstrap dance (see docs/multi-arch-builder.md Option C): nix-rosetta-builder needs an
# existing Linux builder to build its own Lima guest image the first time. The consumer keeps the
# stock `nix.linux-builder` enabled until the Rosetta VM is up, then may disable it.
#
# ## Guest resources
#
# The upstream darwin module comes in through the `darwin` target, so a host sets its own options
# directly. The slot declares no pass-through option for `memory` or `cores`:
#
#     nix-rosetta-builder.memory = "12GiB";   # upstream default 6GiB
#     nix-rosetta-builder.cores = 8;          # upstream default 8; also caps maxJobs
#
# The disk is the exception. The slot asserts a ceiling, `guest.diskSizeMax`, but it does **not**
# set `diskSize`. Upstream's `100GiB` default stands, so this slot changes no existing guest. The
# ceiling exists because the guest disk is a sparse file on the host disk: an oversized guest fills
# the host disk instead of failing its own build.
#
# ⚠️ **Any change to `memory`, `cores` or `diskSize` destroys the guest.** They all feed the
# generated `lima.yaml`, and the daemon compares that file against the installed one. On a
# difference it runs `limactl delete --force` and then `limactl create` (upstream
# `module.nix:336-360`). The guest's own Nix store goes with it, so every cached guest build result
# must be fetched or built again. Change a size once, deliberately, not to chase one failed build.
{
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.kdn.darwin.rosetta-builder;

  # "150GiB" -> 161061273600. Returns null when the string does not parse.
  sizeToBytes =
    text:
    let
      parts = builtins.match "([0-9]+) *([KMGT]?)(i?)B?" text;
      exponents = {
        "" = 0;
        K = 1;
        M = 2;
        G = 3;
        T = 4;
      };
    in
    if parts == null then
      null
    else
      let
        exponent = exponents.${builtins.elemAt parts 1};
        base = if (builtins.elemAt parts 2) == "i" then 1024 else 1000;
      in
      lib.foldl' (acc: _: acc * base) (lib.toInt (builtins.elemAt parts 0)) (lib.range 1 exponent);

  guestNixSettings =
    lib.optionalAttrs (cfg.guest.minFree != null) {
      min-free = lib.mkForce cfg.guest.minFree;
    }
    // lib.optionalAttrs (cfg.guest.maxFree != null) {
      max-free = lib.mkForce cfg.guest.maxFree;
    };
in
{
  options.kdn.darwin.rosetta-builder = {
    enable = lib.mkEnableOption "Rosetta-backed dual-arch (aarch64-linux + x86_64-linux) Nix builder";

    guest.diskSizeMax = lib.mkOption {
      type = lib.types.str;
      default = "150GiB";
      example = "100GiB";
      description = ''
        Hard ceiling on the guest disk. The slot asserts that the effective
        `nix-rosetta-builder.diskSize` stays at or under this value. It does **not** set
        `diskSize`, so upstream's `100GiB` default stands and an existing guest survives untouched.

        The guest disk is a sparse file on the host disk, so the guest cannot fail its own build
        when it grows too far — it fills the host disk instead. The ceiling makes that limit
        explicit.

        `100GiB` was enough for a three-host build on 2026-09-10. Guest free space fell to 19.1 GB,
        but the blocker was the guest's own garbage collector, not the disk size. See
        `guest.minFree`.

        ⚠️ A change to this option alone changes nothing on disk. A change to `diskSize`
        regenerates `lima.yaml` and therefore **destroys and recreates the guest** — see the
        "Guest resources" note at the top of this file.
      '';
    };

    guest.minFree = lib.mkOption {
      type = with lib.types; nullOr (either str int);
      default = null;
      example = 0;
      description = ''
        Overrides `nix.settings.min-free` inside the guest. `null` keeps the upstream value, `5G`.

        The guest collects its own garbage in the middle of a build, and that breaks builds. When
        free space on the guest disk falls under `min-free`, the guest's nix daemon takes the big
        garbage collector lock and deletes store paths until free space passes `max-free`
        (upstream `7G`). A build that still needs a deleted path then fails.

        Measured on 2026-09-10 with a 99 G guest disk: one host-build pass logged 622
        `deleting '/nix/store/…'` lines. A full manual collection freed 72.5 GiB over 9930 paths
        and took guest free space from 19.1 GB to 96.0 GB. After that, every pass deleted nothing.

        Set `0` to stop the guest from collecting garbage on its own. Then you must watch the guest
        disk yourself, because a full disk fails a build too.

        ⚠️ A change here regenerates `lima.yaml`, so it **destroys and recreates the guest** — see
        the "Guest resources" note at the top of this file.
      '';
    };

    guest.maxFree = lib.mkOption {
      type = with lib.types; nullOr (either str int);
      default = null;
      example = "20G";
      description = ''
        Overrides `nix.settings.max-free` inside the guest. `null` keeps the upstream value, `7G`.
        This is the free-space target a guest collection stops at. Raise it together with
        `guest.minFree` when you want fewer, larger collections instead of many small ones.

        ⚠️ A change here destroys and recreates the guest, exactly like `guest.minFree`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A module function, not a plain attribute set: the assertion below must read the consumer's
    # own effective `diskSize`, which a plain attribute set cannot see.
    darwin =
      { config, ... }:
      {
        imports = [
          inputs.nix-rosetta-builder.darwinModules.default
        ];

        # Module default is already true; explicit for clarity.
        nix-rosetta-builder.enable = true;
        # Power the VM off when idle.
        nix-rosetta-builder.onDemand = lib.mkDefault true;
        # Let the VM pull build inputs from public caches, instead of the host uploading everything
        # over the slow VM link (see docs/multi-arch-builder.md "Sharing the store").
        nix.settings.builders-use-substitutes = lib.mkDefault true;

        # Upstream appends this module last to the guest's NixOS module list, so it can override the
        # guest defaults. `mkForce` is needed: upstream sets min-free and max-free as plain values.
        #
        # The option type is `types.attrs`, which merges shallowly. A consumer that also sets this
        # option and also writes `nix.settings` would replace this attribute set, not merge into it.
        nix-rosetta-builder.potentiallyInsecureExtraNixosModule = lib.mkIf (guestNixSettings != { }) {
          nix.settings = guestNixSettings;
        };

        assertions = [
          {
            assertion =
              let
                want = sizeToBytes config.nix-rosetta-builder.diskSize;
                cap = sizeToBytes cfg.guest.diskSizeMax;
              in
              want != null && cap != null && want <= cap;
            message = ''
              nix-rosetta-builder.diskSize is ${config.nix-rosetta-builder.diskSize}, which is
              above the ceiling kdn.darwin.rosetta-builder.guest.diskSizeMax =
              ${cfg.guest.diskSizeMax}. The guest disk is a sparse file on the host disk, so an
              oversized guest fills the host disk. Raise the ceiling on purpose, or lower diskSize.
              A diskSize change destroys and recreates the guest.
            '';
          }
        ];
      };
  };
}
