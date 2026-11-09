# The isolated pkgs-pinning root. It is NOT the den tree: it produces flake outputs only and
# changes no host by itself. One evaluated `pkgs` per `(system, variant)`; a host opts in by
# setting `nixpkgs.pkgs = kdnConfig.self.pkgs.<system>.<variant>` (which then requires the host's
# own `nixpkgs.overlays`/`nixpkgs.config` to be empty — see the guards on those sites).
#
# See docs/tasks/2026-11/pinned-pkgs-single-instantiation/{definition,design-den-root}.md.
{ inputs, self }:
let
  lib = inputs.nixpkgs.lib;
  staticOverlays = import ./overlays.nix { inherit lib; };

  # The uniform nixpkgs config for a pinned set. It must match what an unpinned host would set
  # (allowAliases/allowUnfree/permittedInsecurePackages from kdn.nixpkgs); a host that needs a
  # different config cannot share this pkgs and must stay unpinned or take its own variant.
  baseConfig = {
    allowAliases = true;
    allowUnfree = true;
    # A pinned host can no longer set its own `nixpkgs.config`, so the shared config must permit
    # every insecure package the fleet uses. `olm-3.2.16` (matrix) is the one today.
    permittedInsecurePackages = [ "olm-3.2.16" ];
  };

  mk =
    {
      system,
      extraOverlays ? [ ],
      extraConfig ? { },
    }:
    import inputs.nixpkgs {
      inherit system;
      overlays = [ self.overlays.default ] ++ staticOverlays ++ extraOverlays;
      config = baseConfig // extraConfig;
    };
in
{
  # `<flake>.pkgs.<system>.{default,...}`
  forSystem =
    system:
    {
      default = mk { inherit system; };
    };
}
