# The key-name map every Niri aspect shares, and the one place a chord modifier is spelled.
#
# It mirrors `desktop-sway.nix` (the same 13 friendly names) but it maps them to the names Niri's
# KDL parser accepts. `super` is `Mod`: Niri treats `Mod` as the compositor modifier, and the
# default `mod-key` is `Super`. A consumer that changes `mod-key` changes it here once.
#
# This file declares options and sets no config, so it is safe in every class. It takes `lib`
# only, so it needs no `specialArgs` from the consumer.
{ lib, ... }:
{
  options.kdn.desktop-niri.keys = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {
      alt = "Alt";
      caps-lock = "Caps_Lock";
      ctrl = "Ctrl";
      delete = "Delete";
      lalt = "Alt";
      modifier = "Mod";
      mouse-down = "WheelScrollUp";
      mouse-up = "WheelScrollDown";
      num-lock = "Num_Lock";
      ralt = "Alt";
      shift = "Shift";
      super = "Mod";
      superMod = "Mod";
    };
    example = {
      super = "Super";
    };
    description = ''
      The Niri key and modifier names, by friendly name.

      A Niri aspect reads this map to build a chord, so one change here moves every binding at
      once. `super` is `Mod` because Niri resolves `Mod` through its `mod-key` setting.
    '';
  };
}
