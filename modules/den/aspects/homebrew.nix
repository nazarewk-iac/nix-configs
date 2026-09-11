# The Homebrew concern, as a den aspect. It has no slot ancestor, so this is a first port.
#
# ## Why the aspect exists
#
# `modules/universal/default.nix` configures Homebrew for **every** darwin host, with no switch. It
# turns nix-darwin's `homebrew` module on, it sets three `onActivation` values, and it registers one
# tap per `brew-tap--*` flake input. A developer who adopts these modules very plausibly manages
# Homebrew already, and such a developer objects to all of it. So the whole concern becomes opt-in:
# **inclusion is the switch**, and every list starts empty.
#
# ## What it does
#
# It turns nix-darwin's own `homebrew` module on. It then feeds three consumer-supplied lists to it —
# `taps`, `casks` and `brews` — plus three `onActivation` values. Each value is an option, so the
# aspect itself names no tap, no cask and no formula.
#
# Two `onActivation` values mirror `modules/universal/default.nix`. The third, `cleanup`, does not:
# it defaults to nix-darwin's own `"none"`, because `"zap"` deletes a package a stranger installed
# by hand. This repository writes `"zap"` back in its own consumer, so its opinion is explicit
# instead of inherited. See the option's own description.
#
# ## What it deliberately leaves out
#
# 1. **nix-homebrew.** The tree also imports `inputs.nix-homebrew.darwinModules.nix-homebrew`, and it
#    sets `nix-homebrew.enable`, `nix-homebrew.enableRosetta`, `nix-homebrew.mutableTaps = false` and
#    `nix-homebrew.user`. That module takes over the Homebrew installation itself and it makes every
#    tap immutable. An adopter with a real Homebrew installation loses control of it, so the opinion
#    needs an aspect of its own. This aspect stays compatible with a hand-managed Homebrew.
# 2. **`HOMEBREW_READ_ONLY=1`.** The tree exports that variable from `zsh` and from `fish`. It is
#    correct only while `nix-homebrew.mutableTaps` is false, so it belongs with item 1.
# 3. **The flake-input tap scan.** It reads this repository's own input names, so it cannot move to a
#    standalone aspect. It stays in `modules/universal/default.nix`, behind
#    `kdn.homebrew.tapsFromFlakeInputs`, which defaults to `false`.
#
# DECISION TO REVISE: items 1 and 2 together form a second aspect, `homebrew-nix-managed`. It brings
# the nix-homebrew module, the immutable taps and the read-only shell variable. This port does not
# create it, because no den entity needs it yet.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only — the two
#    arguments every nix-darwin evaluation already gives.
{ ... }:
{
  kdn.homebrew.darwin =
    { config, lib, ... }:
    let
      cfg = config.kdn.homebrew;
    in
    {
      options.kdn.homebrew.taps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Homebrew taps, one name per entry. The empty default is the point of the aspect: it names
          no tap, so a consumer that includes the aspect still gets no tap of somebody else's.

          nix-darwin coerces each string into its own tap submodule, so a plain name is enough.
        '';
        example = [ "example-org/example-tap" ];
      };

      options.kdn.homebrew.casks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Homebrew casks, one name per entry. The consumer supplies every name.
        '';
        example = [ "example-cask" ];
      };

      options.kdn.homebrew.brews = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Homebrew formulae, one name per entry. The consumer supplies every name.
        '';
        example = [ "example-brew" ];
      };

      options.kdn.homebrew.onActivation.upgrade = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Upgrade an outdated formula and an outdated Mac App Store app during activation.

          nix-darwin defaults this to `false`, so that a repeated `darwin-rebuild switch` stays
          idempotent. This aspect mirrors the value the tree sets today.
        '';
      };

      options.kdn.homebrew.onActivation.autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Let Homebrew update itself and every formula during activation. It stays off, so that a
          repeated activation gives one result.
        '';
      };

      options.kdn.homebrew.onActivation.cleanup = lib.mkOption {
        type = lib.types.enum [
          "none"
          "check"
          "uninstall"
          "zap"
        ];
        default = "none";
        description = ''
          What happens to a Homebrew package that the generated Brewfile does not name.

          The default is `"none"`, which is also nix-darwin's own default. It keeps every package a
          consumer installed by hand. This is the one aspect default that does **not** mirror this
          repository's legacy tree, and the reason is damage: `"zap"` removes the package and every
          file of a cask, so a first activation deletes work a stranger never gave to Nix.

          `"zap"` suits a consumer that manages Homebrew from Nix alone. Such a consumer writes the
          value explicitly. This repository does exactly that, in
          `checks/den-mvp/host-darwin/default.nix`, so its own opinion survives the safe default.
        '';
        example = "zap";
      };

      config = {
        # Inclusion is the switch, so the aspect turns the module on with no guard.
        #
        # `lib.mkDefault` on the four scalar values below is deliberate. Measured on 2026-09-11: at
        # plain priority a consumer's own `homebrew.onActivation.cleanup = "none";` throws a
        # conflict instead of an override, and only `lib.mkForce` wins. A `mkDefault` lets a plain
        # consumer value win, which is what an adopter expects.
        homebrew.enable = lib.mkDefault true;

        # The three lists stay at plain priority, and that is also deliberate. A `listOf` merges two
        # plain definitions by concatenation, so a consumer's own `homebrew.casks` **adds** to this
        # one and throws nothing. A `mkDefault` here would make the consumer's list *replace* the
        # value of `kdn.homebrew.casks` instead, which loses data with no warning.
        homebrew.taps = cfg.taps;
        homebrew.casks = cfg.casks;
        homebrew.brews = cfg.brews;

        homebrew.onActivation.upgrade = lib.mkDefault cfg.onActivation.upgrade;
        homebrew.onActivation.autoUpdate = lib.mkDefault cfg.onActivation.autoUpdate;
        homebrew.onActivation.cleanup = lib.mkDefault cfg.onActivation.cleanup;
      };
    };
}
