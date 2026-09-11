# The modem setup, as a den aspect. It ports the `modem` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns NetworkManager and ModemManager on, so an LTE modem gives data and calls.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only.
#
# ## What the port changes
#
# Nothing. Every line is a plain nixpkgs option, and the port is a one-to-one copy.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. Every `enable` below belongs to nixpkgs, and
#    the walk inspects the `kdn` prefix alone.
# 3. **No custom module argument.** The target module below takes `lib` only.
{ ... }:
{
  kdn.hw-modem.nixos =
    { lib, ... }:
    {
      networking.networkmanager.enable = lib.mkDefault true;
      systemd.services.ModemManager.enable = lib.mkDefault true;
      systemd.services.ModemManager.wantedBy = [ "NetworkManager.service" ];
    };
}
