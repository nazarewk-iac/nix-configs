# The Bluetooth stack, as a den aspect. It ports the `bluetooth` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns the BlueZ stack on and it adds the Blueman applet service. The pairing keys live under
# `/var/lib/bluetooth`, so that directory survives a boot.
#
# ## Class list: `nixos` alone
#
# The whole old module sits behind a `nixos` context guard, so the den aspect emits `nixos` only.
#
# ## What the port changes
#
# **The persistence write becomes a read-only output.** The old module writes the state directory
# into the persistence buckets of the `disks` area. This aspect publishes
# `kdn.hw.bluetooth.persist.{directories,files}` instead, and the consumer wires them. It follows
# the `apps` aspect of batch 2.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `lib` only.
{ ... }:
{
  kdn.hw-bluetooth.nixos =
    { lib, ... }:
    {
      options.kdn.hw.bluetooth.persist.directories = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = {
          "sys/config" = [ "/var/lib/bluetooth" ];
        };
        description = ''
          The system directories the Bluetooth stack keeps between boots, grouped by bucket. It is
          read-only.

          The old module writes this list straight into the persistence option of the `disks` area.
          That area has its own aspect, so this aspect publishes the list and the consumer wires it:

              kdn.disks.persist."sys/config".directories =
                config.kdn.hw.bluetooth.persist.directories."sys/config";
        '';
      };

      options.kdn.hw.bluetooth.persist.files = lib.mkOption {
        readOnly = true;
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = ''
          The single system files the Bluetooth stack keeps between boots. The old module names
          none, so the set is empty. It is read-only.
        '';
      };

      config.hardware.bluetooth.enable = true;
      # TODO: move the blueman-applet user config here.
      config.services.blueman.enable = true;
    };
}
