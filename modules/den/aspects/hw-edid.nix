# The EDID tools and the extra display modelines, as a den aspect. It ports the `edid` module of the
# old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# A monitor states its own timings over EDID. A monitor that states them wrong needs an override, so
# this aspect installs the EDID tools and it feeds the extra modelines to the initrd.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only.
#
# ## What the port changes
#
# 1. **`modelines` gets an explicit `default = { }`.** The old option declares no default. The
#    nixpkgs `attrsOf` type supplies an empty set through `emptyValue`, so the behaviour does not
#    move; the explicit default only makes the state readable.
# 2. **The native option replaces the cross-platform package list.** A den target names its class,
#    so this one writes `environment.systemPackages`.
#
# ## No monitor data in this file
#
# A modeline names a real monitor of a real machine, so it is host data. The example below is a
# placeholder, and the default set is empty. A consumer supplies its own modelines.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-edid.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.edid;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.hw.edid.modelines = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = lib.literalExpression ''
          {
            "MON_60" = "    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync";
          }
        '';
        description = ''
          XFree86 modelines, by name. Each name becomes an `edid/<name>.bin` file in the initrd, and
          `hardware.display.outputs.<output>.edid` names that file. A name holds 12 characters or
          fewer.

          The default is the empty set, so a machine with no monitor data adds no modeline. The
          nixpkgs `apply` then returns `null`, which is the same state as a disabled old module.
        '';
      };

      config.environment.systemPackages = filterPackages (
        with pkgs;
        [
          linuxhw-edid-fetcher
          edid-decode
          read-edid
          edido
        ]
      );

      config.hardware.display.edid.modelines = cfg.modelines;
    };
}
