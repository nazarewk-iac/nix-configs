# The NanoKVM setup, as a den aspect. It ports the `nanokvm` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# A NanoKVM presents itself as a USB Ethernet device. This aspect gives that device the stable name
# `usb-nanokvm`, it takes the device away from NetworkManager's automatic handling, and it adds one
# NetworkManager profile that binds to the stable name.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only. The udev rule and `networking.networkmanager` exist on NixOS alone.
#
# ## What the port changes
#
# **The 50-line udev event dump goes.** The old module holds a captured `udevadm monitor` block as a
# comment. That capture names one real device: it holds a MAC-derived interface name and a device
# serial. Both are personal hardware identifiers, so the port drops the comment. The udev rule itself
# needs four keys only — `ID_MODEL`, `ID_MODEL_ID`, `ID_NET_DRIVER` and `SUBSYSTEM` — and each one
# names the product, not the unit. Reproduce the capture with `udevadm monitor --property` when you
# need it.
#
# ## Follow-up
#
# The old module carries a `TODO: systemd-networkd version`. This aspect keeps the NetworkManager
# route unchanged, so the note stays open.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config` and `lib` only.
{ ... }:
{
  kdn.hw-nanokvm.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.hw.nanokvm;
    in
    {
      options.kdn.hw.nanokvm.ethernet.autoConnect = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Let NetworkManager bring the NanoKVM link up as soon as the device appears. The default is
          `false`, so the link comes up on request only. The profile keeps priority -999 either way,
          so any other connection wins.
        '';
      };

      config.services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="net", ENV{ID_MODEL}=="licheervnano", ENV{ID_MODEL_ID}=="1009", ENV{ID_NET_DRIVER}=="rndis_host", ENV{NM_UNMANAGED}="1", NAME="usb-nanokvm"
      '';

      config.networking.networkmanager.ensureProfiles.profiles.nanokvm = {
        connection.id = "usb-nanokvm";
        connection.type = "ethernet";
        connection.interface-name = "usb-nanokvm";
        connection.autoconnect = cfg.ethernet.autoConnect;
        connection.autoconnect-priority = -999;
        ipv4.method = "auto";
        ipv6.method = "auto";
        ipv6.addr-gen-mode = "stable-privacy";
      };
    };
}
