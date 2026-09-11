# The Intel HD Graphics fix, as a den aspect. It ports the `intel-graphics-fix` module of the old
# hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# Mesa crashes on some Intel HD parts. The workaround forces the older `i965` Mesa driver through
# `MESA_LOADER_DRIVER_OVERRIDE`. See
#
#   - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5864
#   - https://gitlab.freedesktop.org/mesa/mesa/-/issues/5600
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only.
#
# ## What the port changes
#
# **The commented-out line becomes a reachable option.** The old module holds one assignment, and it
# is fully commented out, with the note "2026-07-31: watch out for breakages?". So the old module has
# no effect at all today. The port keeps that effect — the default is `null`, which writes nothing —
# and it makes the workaround reachable through `kdn.hw.intel-graphics-fix.mesaLoaderDriverOverride`.
# A consumer that meets the crash sets the value; nobody else changes state.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.hw-intel-graphics-fix.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.hw.intel-graphics-fix;
    in
    {
      options.kdn.hw.intel-graphics-fix.mesaLoaderDriverOverride = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "i965";
        description = ''
          The value of `MESA_LOADER_DRIVER_OVERRIDE`. `null` sets no variable, which is the state of
          the old module today, because its one assignment is commented out.

          Set `"i965"` when Mesa crashes on an Intel HD part. Watch for a breakage after you set it:
          the older driver misses some newer features.
        '';
      };

      config.environment.variables.MESA_LOADER_DRIVER_OVERRIDE = lib.mkIf (
        cfg.mesaLoaderDriverOverride != null
      ) cfg.mesaLoaderDriverOverride;
    };
}
