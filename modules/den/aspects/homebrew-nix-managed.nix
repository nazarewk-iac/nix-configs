# The second half of the Homebrew concern: Nix owns the Homebrew installation itself.
#
# ./homebrew.nix is the base. It turns nix-darwin's `homebrew` module on, and it stays compatible
# with a Homebrew installation a person manages by hand. This file adds the two opinions that the
# base aspect deliberately leaves out, and `includes` brings the base with it.
#
# ## What it does
#
# 1. It imports `inputs.nix-homebrew.darwinModules.nix-homebrew`, and it sets `nix-homebrew.enable`,
#    `nix-homebrew.enableRosetta`, `nix-homebrew.mutableTaps = false` and `nix-homebrew.user`. That
#    module takes over the Homebrew installation and it makes every tap immutable.
# 2. It exports `HOMEBREW_READ_ONLY=1` from `zsh` and from `fish`. The variable is correct only
#    while `mutableTaps` is false, so the export reads the effective value of that option instead of
#    a copy. A consumer that sets `nix-homebrew.mutableTaps = true` gets no export, and no wrong
#    promise.
#
# Every value comes from `modules/universal/default.nix:229-257`, which configures the same two
# opinions for the darwin hosts of this repository.
#
# ## What it deliberately leaves out
#
# **The flake-input tap scan.** It reads the `brew-tap--<owner>--<repo>` input names of the flake
# that owns the tree, so it cannot move to a standalone aspect: an adopter's flake holds other
# names. It stays in `modules/universal/default.nix`, behind `kdn.homebrew.tapsFromFlakeInputs`,
# which defaults to `false`.
#
# ## What this aspect costs a consumer
#
# nix-homebrew moves the Homebrew prefix under Nix control. A consumer with a real Homebrew
# installation loses direct control of every tap. That is why the base aspect does not carry the
# opinion, and why this file exists separately. No host and no check of this repository includes it
# today.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only —
#    the three arguments every nix-darwin evaluation already gives.
{ inputs, kdn, ... }:
{
  # The base aspect always comes with this one. It declares `kdn.homebrew.taps`, `.casks`, `.brews`
  # and the three `onActivation` values, and it turns nix-darwin's own `homebrew` module on. den
  # collapses the diamond, so a consumer that includes both holds one copy of each.
  kdn.homebrew-nix-managed.includes = [ kdn.homebrew ];

  kdn.homebrew-nix-managed.darwin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.homebrew.nixManaged;
    in
    {
      imports = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
      ];

      options.kdn.homebrew.nixManaged.user = lib.mkOption {
        type = lib.types.str;
        default = if config.system.primaryUser != null then config.system.primaryUser else "";
        defaultText = lib.literalExpression "config.system.primaryUser";
        example = "adopter";
        description = ''
          The user who owns the Homebrew directories. nix-homebrew declares `nix-homebrew.user` as a
          plain `str` with no default, so a value is mandatory.

          This is a per-machine value, so the aspect names no user of its own. The default reads the
          consumer's own `system.primaryUser`, which is the user that runs `darwin-rebuild`. When
          that option is `null` too, the value stays empty and a warning below says so.
        '';
      };

      config = lib.mkMerge [
        {
          # `lib.mkDefault` on every scalar, for the reason ./homebrew.nix records: at plain
          # priority a consumer's own value collides instead of overriding.
          nix-homebrew.enable = lib.mkDefault true;
          nix-homebrew.enableRosetta = lib.mkDefault pkgs.stdenv.hostPlatform.isAarch64;

          # Immutable taps are the point of the aspect: Nix owns the tap set, so nothing else may
          # change it. The read-only export below reads this same option.
          nix-homebrew.mutableTaps = lib.mkDefault false;
          nix-homebrew.user = lib.mkDefault cfg.user;

          warnings = lib.optional (cfg.user == "") ''
            kdn.homebrew.nixManaged.user is empty, and nix-homebrew needs the user that owns the
            Homebrew directories. Set `kdn.homebrew.nixManaged.user`, or set
            `system.primaryUser`.
          '';
        }

        # `HOMEBREW_READ_ONLY=1` tells the `brew` CLI that it may change nothing. It is correct only
        # while the taps are immutable, so it follows the effective option value and never a copy.
        (lib.mkIf (!config.nix-homebrew.mutableTaps) {
          programs.zsh.interactiveShellInit = ''
            export HOMEBREW_READ_ONLY=1
          '';
          programs.fish.interactiveShellInit = ''
            set -gx HOMEBREW_READ_ONLY 1
          '';
        })
      ];
    };
}
