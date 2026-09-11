# The `profile/machine/hetzner` module of the old tree, as one den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It makes a Hetzner Cloud virtual machine boot: the virtio initrd modules, grub instead of
# systemd-boot, one ext4 root, and one systemd-networkd link with a static IPv6 address.
#
# ## Class list: `nixos`
#
# The old module is nixos-only (`hetzner/default.nix:22`).
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.profile.machine.baseline.enable` becomes an `includes` entry.**
# 3. **`ipv6Address` gets a `null` default.** The old option is `types.str` with **no** default, so
#    every read fails until a host sets it. `den-eval-instantiate` forces this pair alone, so the
#    port uses `nullOr str` with `null`. The old code already tests `!= null` at `:65`, which proves
#    the intent.
# 4. **The two device paths become options.** The old module hard-codes `/dev/sda` and `/dev/sda1`.
#    A den consumer names its own disk.
# 5. **The root filesystem writes at `mkDefault`.** The old lines write at plain priority, and the
#    bare consumer of `den-eval-instantiate` already writes a tmpfs root at plain priority. Two
#    plain definitions of one leaf stop the evaluation. A `mkDefault` lets a real host keep its own
#    root and lets the bare consumer keep the tmpfs.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** A host name and an address are entity facts, so both arrive through an
#    option a consumer sets.
# 2. **No reachable `enable` option.**
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ kdn, ... }:
{
  kdn.profile-hetzner.includes = [ kdn.profile-baseline ];

  kdn.profile-hetzner.nixos =
    { config, lib, ... }:
    let
      cfg = config.kdn.profile-hetzner;
    in
    {
      options.kdn.profile-hetzner.ipv6Address = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = ''
          The static IPv6 address of this machine, with its prefix length. `null` leaves the link
          on IPv4 alone.

          See https://docs.hetzner.com/cloud/servers/static-configuration/.
        '';
      };

      options.kdn.profile-hetzner.rootDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda1";
        description = "The partition that holds the root filesystem.";
      };

      options.kdn.profile-hetzner.bootDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda";
        description = "The disk grub installs its boot record on.";
      };

      config = lib.mkMerge [
        {
          # BOOT
          boot.initrd.availableKernelModules = [
            "ata_piix"
            "virtio_pci"
            "virtio_scsi"
            "xhci_pci"
            "sd_mod"
            "sr_mod"
          ];
          boot.kernelModules = [ ];

          # TODO: it is not clear whether Hetzner really needs grub.
          boot.loader.systemd-boot.enable = lib.mkForce false;

          boot.loader.grub.enable = lib.mkDefault true;
          # a conflict inside specialisation.boot-debug
          boot.loader.grub.splashImage = lib.mkForce null;
          boot.loader.grub.device = cfg.bootDevice;

          fileSystems."/".device = lib.mkDefault cfg.rootDevice;
          fileSystems."/".fsType = lib.mkDefault "ext4";
        }
        {
          networking.networkmanager.enable = false;

          systemd.network.networks."00-wan" = {
            matchConfig.Type = "ether";
            matchConfig.Driver = "virtio_net";
            networkConfig.DHCP = "ipv4";
            networkConfig.IPv6AcceptRA = "no";
            networkConfig.IPv6SendRA = "no";
            networkConfig.LinkLocalAddressing = "ipv4";
            linkConfig.RequiredForOnline = "routable";
            # see https://docs.hetzner.com/cloud/servers/static-configuration/
            gateway = [ "fe80::1" ];
            address = lib.optional (cfg.ipv6Address != null) cfg.ipv6Address;
          };
        }
      ];
    };
}
