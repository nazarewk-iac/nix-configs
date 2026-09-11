# One declaration of `kdn.graphical`, shared by every aspect that ships a graphical extra.
#
# ## What the option means
#
# Several aspects install one extra package only on a machine with a desktop. The old tree reads
# `config.kdn.desktop.enable` for that test. A den aspect declares no reachable `enable` option, so
# the test needs its own switch. This file declares that switch once.
#
# A desktop aspect writes `kdn.graphical = lib.mkDefault true;` in its own target. A consumer with
# no desktop leaves the value `false` and gets no graphical extra.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that needs this option writes one line in its target module:
#
#     imports = [ ../common/graphical.nix ];
#
# Any number of such aspects then load together, and the option keeps exactly one declaration. The
# shape copies ./source-repo.nix and ./host-name.nix.
#
# ## The per-aspect switch stays
#
# Each aspect keeps its own option, for example `kdn.hw.qmk.graphical`. That option reads
# `config.kdn.graphical` as its default. So one consumer line turns every graphical extra on, and a
# consumer still sets one aspect alone at a higher priority.
#
# This file declares an option and sets no config, so it is safe in every class. It takes `lib`
# only, so it needs no `specialArgs` from the consumer.
{ lib, ... }:
{
  options.kdn.graphical = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      This machine runs a desktop.

      An aspect that ships a graphical extra reads this option as the default of its own switch.
      The old tree reads `kdn.desktop.enable` for the same test. A den aspect declares no reachable
      `enable`, so a consumer states this opinion instead.
    '';
  };
}
