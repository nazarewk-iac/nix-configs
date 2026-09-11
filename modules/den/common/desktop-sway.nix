# Two declarations that every sway aspect shares: the key-name map and the environment target name.
#
# ## What the two options mean
#
# `kdn.desktop-sway.keys` maps a friendly name to a sway modifier or key name. Eight sway aspects
# read it to build a keybinding. The old tree keeps the same map in one file and imports it.
#
# `kdn.desktop-sway.envsTarget` names the systemd user target that carries the sway session
# environment. Two aspects order their own unit after it. The old tree computes the name from a
# prefix and a unit list; a plain string is enough for a reader, and a consumer that renames the
# target states the new name here.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that needs these options writes one line in its target module:
#
#     imports = [ ../common/desktop-sway.nix ];
#
# Any number of such aspects then load together, and each option keeps exactly one declaration. The
# shape copies ./host-name.nix and ./graphical.nix.
#
# ## Why `envsTarget` is flat
#
# A later batch ports the sway session module, and that module owns a whole unit-name tree. A flat
# name cannot collide with such a tree, so this file stays out of its way.
#
# This file declares two options and sets no config, so it is safe in every class. It takes `lib`
# only, so it needs no `specialArgs` from the consumer.
{ lib, ... }:
{
  options.kdn.desktop-sway.keys = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {
      alt = "Alt";
      caps-lock = "lock";
      ctrl = "Control";
      delete = "Delete";
      lalt = "Mod1";
      modifier = "Mod3";
      mouse-down = "Button4";
      mouse-up = "Button5";
      num-lock = "Mod2";
      ralt = "Mod5";
      shift = "Shift";
      super = "Super";
      superMod = "Mod4";
    };
    example = {
      super = "Mod4";
    };
    description = ''
      The sway key and modifier names, by friendly name.

      `man 5 sway` lists the accepted names. A sway aspect reads this map to build a keybinding, so
      one change here moves every binding at once.
    '';
  };

  options.kdn.desktop-sway.envsTarget = lib.mkOption {
    type = lib.types.str;
    default = "kdn-sway-envs.target";
    example = "sway-session.target";
    description = ''
      The name of the systemd user target that carries the sway session environment.

      An aspect that starts a session service orders its unit after this target.
    '';
  };
}
