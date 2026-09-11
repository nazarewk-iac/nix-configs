/*
  Personal monitor data for `kdn.hw.edid`.

  This file is a module, not a data value. It assigns an option that
  `modules/universal/hw/edid/default.nix` declares, so that module holds no monitor value.

  The body reads no module argument, so the file is a plain attribute set with no function head.
  nixpkgs `lib/modules.nix` accepts both forms.

  `modules/universal/default.nix` imports this file behind `builtins.pathExists`. An adopter
  deletes the file and `kdn.hw.edid.modelines` falls back to the empty set.

  The three entries below match the nixpkgs `hardware.display.edid.modelines` example
  verbatim. `hosts/brys/default.nix` names `PG278Q_120.bin`, so the names must not change.
*/
{
  config.kdn.hw.edid.modelines = {
    "PG278Q_60" = "    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync";
    "PG278Q_120" = "   497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync";
    "U2711_60" = "     241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync";
  };
}
