# Render the real fork jj slot config to a TOML file.
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
(pkgs.formats.toml { }).generate "jj-fork-config.toml" rendered.config.kdn.jj.config
