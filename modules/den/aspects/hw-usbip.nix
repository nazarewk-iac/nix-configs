# The USB/IP setup, as a den aspect. It ports the `usbip` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# USB/IP shares a USB device over the network. See https://wiki.archlinux.org/title/USB/IP.
#
# This aspect loads the two kernel modules, it runs `usbipd`, it adds a template unit that binds one
# bus id on request, and it opens the TCP port on one interface.
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only. The `package` default reads `boot.kernelPackages`, which exists on NixOS alone. The
# old module carries a `TODO: research whether USB/IP is possible on Darwin`; that note stays open.
#
# ## What the port changes
#
# **The `package` default drops its context test.** The old default reads
# `if kdnConfig.moduleType == "nixos" then config.boot.kernelPackages.usbip else pkgs.emptyFile`. This
# target is the `nixos` class, so the test always took the first branch, and the port keeps that
# branch alone.
#
# The native option replaces the cross-platform package list, as every den target does.
#
# ## One preserved oddity
#
# `usbip-bind@.service` requires `usbipd.target`, and no such unit exists — the daemon unit is
# `usbipd.service`, which the same list names under `after`. The port keeps the line unchanged,
# because a behaviour change belongs to a separate commit. Fix it later.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. `systemd.services.<name>.enable` is a nixpkgs
#    option, and the walk inspects the `kdn` prefix alone.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-usbip.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.usbip;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };

      target = "network";
    in
    {
      options.kdn.hw.usbip.package = lib.mkOption {
        type = lib.types.package;
        default = config.boot.kernelPackages.usbip;
        defaultText = lib.literalExpression "config.boot.kernelPackages.usbip";
        description = ''
          The `usbip` build the daemon and the bind unit call. The default follows the running
          kernel, because the tool and the kernel modules move together.
        '';
      };

      options.kdn.hw.usbip.bindInterface = lib.mkOption {
        type = lib.types.str;
        default = "wg0";
        example = "*";
        description = ''
          The network interface that reaches the daemon port. `"*"` opens the port on every
          interface; any other value opens it on that interface alone.

          The default is a WireGuard interface, so the share stays inside the tunnel.
        '';
      };

      options.kdn.hw.usbip.bindPort = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 3240;
        description = ''
          The TCP port `usbipd` listens on. 3240 is the registered USB/IP port.
        '';
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages [ cfg.package ];

          boot.kernelModules = [
            "vhci-hcd"
            "usbip_host"
          ];

          systemd.services.usbipd.description = "USB/IP daemon";
          systemd.services.usbipd.after = [ "${target}.target" ];
          systemd.services.usbipd.wantedBy = [ "${target}.target" ];
          systemd.services.usbipd.serviceConfig.ExecStart =
            "${cfg.package}/bin/usbipd --tcp-port=${toString cfg.bindPort}";

          systemd.services."usbip-bind@".description = "USB/IP daemon";
          # `usbipd.target` does not exist. The line is unchanged from the old module; see the header.
          systemd.services."usbip-bind@".requires = [ "usbipd.target" ];
          systemd.services."usbip-bind@".after = [
            "usbipd.service"
            "${target}.target"
          ];
          systemd.services."usbip-bind@".wantedBy = [ "${target}.target" ];
          systemd.services."usbip-bind@".serviceConfig.Type = "oneshot";
          systemd.services."usbip-bind@".serviceConfig.RemainAfterExit = true;
          systemd.services."usbip-bind@".serviceConfig.ExecStart = "${cfg.package}/bin/usbip bind --busid %i";
          systemd.services."usbip-bind@".serviceConfig.ExecStop =
            "${cfg.package}/bin/usbip unbind --busid %i";

          # The template's `wantedBy` would start an instance named after the target itself. This
          # line stops that one instance.
          systemd.services."usbip-bind@${target}".enable = false;
        }
        (lib.mkIf (cfg.bindInterface == "*") {
          networking.firewall.allowedTCPPorts = [ cfg.bindPort ];
        })
        (lib.mkIf (cfg.bindInterface != "*") {
          networking.firewall.interfaces.${cfg.bindInterface}.allowedTCPPorts = [ cfg.bindPort ];
        })
      ];
    };
}
