/*
  Personal wallpaper data for `stylix.image`.

  This file is a module, not a data attribute set. It assigns the stylix option that
  `modules/universal/_stylix.nix` used to hold, so that module names no personal host.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file and `_stylix.nix` falls back to a nixpkgs wallpaper.

  The guard copies `_stylix.nix`. `stylix.*` exists only for the four module types that import a
  stylix module, so an unguarded assignment breaks the `root` and `checks` module types.

  `lib.mkDefault` is mandatory, and it reproduces today's priority exactly.
  `modules/universal/profile/user/{sn,bn}` each assign `stylix.image` at priority 100, so a
  priority-100 definition here would conflict with theirs.
*/
{
  lib,
  pkgs,
  kdnConfig,
  ...
}:
lib.optionalAttrs
  (kdnConfig.util.isOfType [
    "nixos"
    "home-manager"
    "darwin"
    "nix-on-droid"
  ])
  {
    config.stylix.image = lib.mkDefault (
      pkgs.fetchurl {
        # non-expiring share link
        url = "https://nc.nazarewk.pw/s/XSR3x6AkwZAiyBo/download/13754-mushrooms-toadstools-glow-photoshop-3840x2160.jpg";
        sha256 = "sha256-1d/kdFn8v0i1PTeOPytYNUB1TxsuBLNf4+nRgSOYQu4=";
      }
    );
  }
