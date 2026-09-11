# The host output surface, as a den aspect. It ports the whole `outputs` area of the old tree.
#
# Old path:
# modules/universal/outputs/
#
# The old tree keeps every byte. This file is the parallel den implementation.
#
# ## What it is for
#
# `tools/kdnctl/internal/host/base.go` evaluates `kdn.outputs.host` and reads `luksVolumes`. Each
# entry gives the four JSON keys that tool unmarshals: `name`, `keyFile`, `headerPath` and
# `cryptsetupName`. So the shape of the list is a hard contract with a Go program, and the port keeps
# every key name.
#
# ## What the port changes
#
# 1. **The option becomes writable, and it gains a type.** The old option is `readOnly`, it declares
#    no type, and its default reads `kdn.disks.luks.volumes` of the same evaluation. den has no disk
#    aspect in this batch, and a `readOnly` option with a computed default gives a consumer no way to
#    supply the list. So the option now carries `listOf (submodule …)`, a default of `[ ]`, and the
#    consumer writes it.
# 2. **The consumer wires the disk data.** One line does it, and it stays outside this aspect:
#
#        kdn.outputs.host.luksVolumes = lib.pipe config.kdn.disks.luks.volumes [
#          lib.attrsets.attrsToList
#          (builtins.filter (e: e.value.keyFile != null))
#          (map (e: {
#            inherit (e) name;
#            inherit (e.value) keyFile;
#            cryptsetupName = e.value.name;
#            headerPath = e.value.header.path;
#          }))
#        ];
#
#    The disk aspect lands in batch 4. When it lands, that batch or the host adds this one line, and
#    the tool reads the same list as before.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No reachable `enable` option.** Inclusion is the switch. This aspect declares one option and
#    it emits nothing.
# 3. **No custom module argument.** The target module below takes `lib` only.
{ ... }:
{
  kdn.outputs-host.nixos =
    { lib, ... }:
    {
      options.kdn.outputs.host.luksVolumes = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options.name = lib.mkOption {
              type = lib.types.str;
              description = "The name of the volume, as the disk configuration names it.";
            };

            options.keyFile = lib.mkOption {
              type = lib.types.str;
              description = "The path of the key file that unlocks the volume.";
            };

            options.cryptsetupName = lib.mkOption {
              type = lib.types.str;
              description = "The name cryptsetup gives to the mapped device.";
            };

            options.headerPath = lib.mkOption {
              type = lib.types.str;
              description = "The path of the detached LUKS header.";
            };
          }
        );
        default = [ ];
        example = lib.literalExpression ''
          [
            {
              name = "main";
              keyFile = "/var/lib/secrets/main.key";
              cryptsetupName = "main-crypted";
              headerPath = "/dev/disk/by-partlabel/main-header";
            }
          ]
        '';
        description = ''
          Every LUKS volume of this host that carries a key file. A host tool reads this list, so
          each key name is a contract.
        '';
      };
    };
}
