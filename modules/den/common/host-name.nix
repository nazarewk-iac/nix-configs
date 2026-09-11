# One declaration of `kdn.hostName`, shared by every aspect that needs the machine's own name.
#
# ## What the option means
#
# Seven areas of the old tree read `config.kdn.hostName` — `disks`, `fs`, `hw`, `networking`,
# `profile`, `services` and `virtualisation`. Each one needs one string: the name of the machine it
# configures. This file declares that string once.
#
# ## Why a separate file, and why an import by path
#
# The module system rejects two inline declarations of one option. It does dedupe an import **by
# path**. So every aspect that needs this option writes one line in its target module:
#
#     imports = [ ../common/host-name.nix ];
#
# Any number of such aspects then load together, and the option keeps exactly one declaration. The
# shape copies ./source-repo.nix.
#
# ## The default reads the native option
#
# The old tree gets the value from the flake: `flake.nix` writes `lib.mkDefault kdnConfig.hostName`
# for every host. den has no such outer writer, so the default reads `networking.hostName`, which
# both the NixOS class and the nix-darwin class declare.
#
# nix-darwin types the option `nullOr (strMatching …)` and defaults it to **null**. So the `null`
# branch below is reachable, and a darwin consumer that wants a real value sets
# `networking.hostName`. On a class that declares no `networking` option, `or null` returns null and
# the value is the empty string. Measured on 2026-09-11.
#
# This file declares an option and sets no config, so it is safe in every class. It takes `config`
# and `lib` only, so it needs no `specialArgs` from the consumer.
{ config, lib, ... }:
{
  options.kdn.hostName = lib.mkOption {
    type = lib.types.str;
    default =
      let
        name = config.networking.hostName or null;
      in
      if name == null then "" else name;
    defaultText = lib.literalExpression "config.networking.hostName";
    example = "my-laptop";
    description = ''
      The name of this machine. It defaults to `networking.hostName`, and it is the empty string
      when that option is absent or null.
    '';
  };
}
