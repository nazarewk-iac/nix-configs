# Render the real fork jj slot artifacts for the test suite.
#
# It returns two attributes:
#   toml    - the rendered jj config, exported as JJ_FORK_CONFIG_TOML
#   prePush - the pre-push hook SCRIPT, exported as KDN_JJ_PRE_PUSH_SH
#
# `prePush` is the plain script, not the `writeShellApplication` wrapper. The
# wrapper exports `runtimeEnv` inside itself, so a caller cannot override the
# pattern lists — and `test_prepush.py` must set them per case, including the
# empty-list case. The `devenv` slot target is a `deferredModule`, so the
# wrapper's store path is unreachable without a full module evaluation anyway.
#
# Both the flake check and the interactive devenv use this. The check has the
# full flake inputs; the devenv only has its own inputs. So the caller passes
# the pieces explicitly:
#
#   mkSlots  - lib.kdn.mkSlots (from lib/slots/default.nix)
#   slotsPath - path to modules/slots
#   nixConfigs - the nix-configs flake (needed as the `nix-configs` special input;
#                the fork slot reads it for the fork-help doc path)
#   extraInputs - the rest of the inputs merged under specialArgs.inputs
#
# The fixture remotes MUST be named "fork" and "upstream": the rendered revset
# aliases bake those names in (for example `trunk() = main@fork`). The denied
# patterns use PLACEHOLDER-* only — no sensitive term ever appears here.
{
  pkgs,
  mkSlots,
  slotsPath,
  nixConfigs,
  extraInputs ? { },
}:
let
  rendered = mkSlots {
    slotModules = [
      slotsPath
      {
        kdn.jj.enable = true;
        kdn.jj.fork.enable = true;
        kdn.jj.fork.remote = "fork";
        kdn.jj.upstream.remote = "upstream";
        kdn.jj.fork.deniedFilePatterns = [
          "PLACEHOLDER-SENSITIVE"
          "PLACEHOLDER-PREFIX-"
        ];
        kdn.jj.fork.deniedMessagePatterns = [
          "PLACEHOLDER-SENSITIVE"
        ];
      }
    ];
    specialArgs = {
      inherit pkgs;
      inputs = extraInputs // {
        nix-configs = nixConfigs;
      };
    };
  };
in
{
  toml = (pkgs.formats.toml { }).generate "jj-fork-config.toml" rendered.config.kdn.jj.config;
  prePush = slotsPath + "/jj/pre-push.sh";
}
