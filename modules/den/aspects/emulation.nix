# Wine, as a den aspect. It ports the whole `emulation` area of the old tree.
#
# Old path:
# modules/universal/emulation/
#
# The old tree keeps every byte. This file is the parallel den implementation.
#
# ## One aspect, one class
#
# The area holds one module, `emulation/wine`. Its whole effect is one `kdn.apps` entry, and
# `kdn.apps` is a `homeManager` aspect. So `emulation-wine` serves the `homeManager` class alone and
# it includes `apps`.
#
# ## What the port changes
#
# 1. **The `enable` option is gone.** Inclusion is the switch, so the `ifHMParent` forward and the
#    `hasParentOfAnyType` guard both disappear.
# 2. **The x86 assertion becomes a `lib.mkIf`.** The old module asserts
#    `pkgs.stdenv.hostPlatform.isx86`. An aspect must evaluate in a bare consumer on every platform,
#    and a false assertion stops that evaluation. A test alone is not enough either: on
#    aarch64-darwin, nixpkgs throws "i686 Linux package set can only be used with the x86 family."
#    the moment it evaluates `wine-wayland` at all. That throw escapes
#    ../common/filter-packages.nix, because the first filter reads `p.meta.broken` and a throw there
#    runs outside the `tryEval`. Measured 2026-09-11. So the whole entry sits behind `lib.mkIf`,
#    which drops the definition before anything forces the package.
# 3. **The desktop assertion becomes this comment.** The old module also asserts
#    `config.kdn.desktop.enable`. den has no desktop aspect yet, and a consumer that includes this
#    aspect asks for Wine by name.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch. The `kdn.apps.wine.enable` write
#    below sits inside an `attrsOf submodule` of another aspect, so it is out of reach.
# 3. **No custom module argument.** The target module below takes `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.emulation-wine.includes = [ kdn.apps ];

  kdn.emulation-wine.homeManager =
    { lib, pkgs, ... }:
    {
      config = lib.mkIf pkgs.stdenv.hostPlatform.isx86 {
        kdn.apps.wine.enable = true;
        kdn.apps.wine.package.original = pkgs.wine-wayland;
        kdn.apps.wine.dirs.data = [ "/.wine" ];
      };
    };
}
