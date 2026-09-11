# The `rosetta-builder` slot, as a den aspect.
#
# `modules/slots/rosetta-builder/default.nix` stays in place and keeps working. This file is the
# parallel den implementation. The two share no code today, on purpose: a shared helper would tie
# the deprecated tree to the new one.
#
# This slot comes first because it is the smallest slot that targets `darwin`, and because
# checkpoint 002 wants exactly this module as a plain drop-in for an external adopter.
#
# ## Two deliberate limits
#
# 1. **The aspect takes no entity argument.** An aspect that reads `{ host, ... }` resolves to an
#    empty module across the export boundary, with no warning. That is condition 2 of the 004
#    spike. A consumer that needs host data sets a plain option instead.
# 2. **The aspect declares no `enable` option.** Inclusion is the switch: a den entity includes the
#    aspect, and an adopter imports the resolved module. A second declaration of
#    `kdn.darwin.rosetta-builder.enable` would also collide with the slot in one module set.
#
# ## Guest resources
#
# `memory`, `cores` and `diskSize` need no pass-through option. Upstream declares all three
# (`module.nix:58`, `:68`, `:76`), and the `darwin` target hands the upstream module to the
# consumer's own module set, so a consumer writes `nix-rosetta-builder.memory = "12GiB";` directly.
#
# The aspect declares three options upstream has none of:
#
#   * `guest.diskSizeMax` asserts a ceiling on the effective `diskSize`. It sets no size.
#   * `guest.minFree` and `guest.maxFree` override the guest's own garbage collector. Upstream bakes
#     `min-free = "5G"` and `max-free = "7G"` into `package.nix:68-69` and exposes no option.
#
# ⚠️ **A change to `memory`, `cores`, `diskSize`, `minFree` or `maxFree` destroys the guest.** Each
# one feeds the generated `lima.yaml`. The start script compares that file against the installed
# one (`module.nix:335`); on a difference it runs `limactl delete --force` (`module.nix:357`) and
# then `limactl create` (`module.nix:360`). The guest's own Nix store goes with it, so every cached
# guest build result must be fetched or built again. Change one of these once, on purpose.
#
# Every default below keeps `lima.yaml` byte-identical: the two free-space options default to
# `null`, and `diskSizeMax` sets nothing at all.
{ inputs, ... }:
{
  # A module function, not a plain attribute set. The assertion below reads the consumer's own
  # effective `nix-rosetta-builder.diskSize`, and a plain attribute set cannot see it. `config` and
  # `lib` are the two arguments every nix-darwin evaluation already gives, so rule 3 holds.
  kdn.rosetta-builder.darwin =
    { config, lib, ... }:
    let
      cfg = config.kdn.rosetta-builder;

      # "150GiB" -> 161061273600. Returns null when the text does not parse.
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
      imports = [
        inputs.nix-rosetta-builder.darwinModules.default
      ];

      options.kdn.rosetta-builder.guest.diskSizeMax = lib.mkOption {
        type = with lib.types; nullOr str;
        default = "150GiB";
        example = null;
        description = ''
          Hard ceiling on the guest disk. The aspect asserts that the effective
          `nix-rosetta-builder.diskSize` stays at or under this value. It does **not** set
          `diskSize`, so upstream's `100GiB` default stands and an existing guest survives.

          The guest disk is a sparse file on the host disk, so the guest cannot fail its own build
          when it grows too far — it fills the host disk instead. The ceiling makes that limit
          explicit.

          Set `null` to drop the ceiling. Then no assertion runs, and you watch the host disk
          yourself.

          A change to this option alone changes nothing on disk. A change to `diskSize` regenerates
          `lima.yaml` and therefore destroys the guest — see the "Guest resources" note at the top
          of this file.
        '';
      };

      options.kdn.rosetta-builder.guest.minFree = lib.mkOption {
        type = with lib.types; nullOr (either str int);
        default = null;
        example = 0;
        description = ''
          Overrides `nix.settings.min-free` inside the guest. `null` keeps the upstream value, `5G`.

          The guest collects its own garbage in the middle of a build, and that breaks builds. When
          free space on the guest disk falls under `min-free`, the guest's nix daemon takes the big
          garbage collector lock and deletes store paths until free space passes `max-free`
          (upstream `7G`). A build that still needs a deleted path then fails.

          Set `0` to stop the guest from collection of its own garbage. Then you must watch the
          guest disk yourself, because a full disk fails a build too.

          ⚠️ A change here regenerates `lima.yaml`, so it **destroys and recreates the guest** — see
          the "Guest resources" note at the top of this file.
        '';
      };

      options.kdn.rosetta-builder.guest.maxFree = lib.mkOption {
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

      config = {
        # The upstream default is already true (`module.nix:31-33`). It stays explicit here.
        # `lib.mkDefault` on all three: at plain priority a consumer's own value throws a conflict
        # instead of an override, so an adopter would need `lib.mkForce` to turn the guest off.
        nix-rosetta-builder.enable = lib.mkDefault true;
        # Power the guest off when it is idle.
        nix-rosetta-builder.onDemand = lib.mkDefault true;
        # Let the guest pull build inputs from a public cache. Otherwise the host uploads every
        # input over the slow guest link — see docs/multi-arch-builder.md, "Sharing the store".
        nix.settings.builders-use-substitutes = lib.mkDefault true;

        # Upstream appends this module last to the guest's NixOS module list, so it can override the
        # guest defaults. `mkForce` is needed: upstream sets `min-free` and `max-free` as plain
        # values in `package.nix:68-69`.
        #
        # The option type is `types.attrs`, which merges shallowly. A consumer that also sets this
        # option and also writes `nix.settings` replaces this attribute set instead of a merge into
        # it.
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
              cfg.guest.diskSizeMax == null || (want != null && cap != null && want <= cap);
            message = ''
              nix-rosetta-builder.diskSize is ${config.nix-rosetta-builder.diskSize}, which is
              above the ceiling kdn.rosetta-builder.guest.diskSizeMax =
              ${toString cfg.guest.diskSizeMax}. The guest disk is a sparse file on the host disk,
              so an oversized guest fills the host disk. Raise the ceiling on purpose, lower
              diskSize, or set the ceiling to null. A diskSize change destroys and recreates the
              guest.
            '';
          }
        ];
      };
    };
}
