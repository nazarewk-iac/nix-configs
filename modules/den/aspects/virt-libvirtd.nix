# libvirtd and virt-manager, as a den aspect. It ports
# `modules/universal/virtualisation/libvirtd/default.nix`.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It runs libvirtd with QEMU, a software TPM and `virtiofsd`, it redirects a USB device into a guest
# over SPICE, and it keeps the virtual bridge out of NetworkManager. It installs the guest tools and
# `virt-manager`.
#
# ## Two aspects it no longer turns on
#
# The old module writes `kdn.hw.gpu.vfio.enable` and `kdn.programs.dconf.enable`. An aspect must not
# write another aspect's option, so the consumer includes those two aspects itself. `virt-manager`
# needs dconf for its own settings, so a consumer that wants a working `virt-manager` includes the
# dconf aspect.
#
# ## The Windows driver image becomes an option
#
# The old module links `pkgs.virtio-win` into the home directory. That package carries an unfree
# license, so a consumer with the default nixpkgs settings cannot evaluate it. The aspect declares
# `windowsDrivers` instead, `null` by default, and it links the package only when the consumer names
# one.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch.
# 2. **`kdn.env.packages` does not survive.** The target writes `environment.systemPackages`.
#    Design B.
# 3. **The two cross-aspect writes go.** See above.
# 4. **The Home Manager forward becomes a second class.** The old module pushes its home part through
#    `home-manager.sharedModules`. A den consumer includes the `homeManager` class itself.
# 5. **The persist writes become output options.** See below.
#
# ## The persist directories become read-only outputs
#
#     # the nixos class
#     kdn.disks.persist."usr/data".directories = config.kdn.virtualisation.libvirtd.persist.usrData;
#
# The `homeManager` class publishes its own `persist.usrData`, relative to the home directory.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** Each target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.virt-libvirtd.nixos =
    { lib, pkgs, ... }:
    let
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.virtualisation.libvirtd.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage. The consumer wires the list
          into its own persistence option.
        '';
      };

      config = {
        virtualisation.spiceUSBRedirection.enable = true;
        # see https://nixos.wiki/wiki/Virt-manager
        # see https://nixos.wiki/wiki/Libvirt
        virtualisation.libvirtd.enable = true;
        virtualisation.libvirtd.qemu.swtpm.enable = true;
        virtualisation.libvirtd.qemu.vhostUserPackages = with pkgs; [
          virtiofsd
        ];

        networking.firewall.checkReversePath = false;
        networking.networkmanager.unmanaged = [ "interface-name:virbr*" ];
        # TODO: is it needed?
        networking.firewall.trustedInterfaces = [ "virbr*" ];

        environment.systemPackages = filterPackages (
          with pkgs;
          [
            guestfs-tools
            libguestfs
            libvirt
            virt-manager
            cloud-utils # cloud-localds for a cloud image guest
          ]
        );

        kdn.virtualisation.libvirtd.persist.usrData = [
          "/var/lib/libvirt/images"
          "/var/lib/libvirt"
          "/var/lib/swtpm-localca"
        ];
      };
    };

  kdn.virt-libvirtd.homeManager =
    { config, lib, ... }:
    let
      cfg = config.kdn.virtualisation.libvirtd;
    in
    {
      options.kdn.virtualisation.libvirtd.windowsDrivers = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.virtio-win";
        description = ''
          The image that holds the Windows guest drivers. `null` links no image.

          The consumer names the package, because the usual one carries an unfree license.
        '';
      };

      options.kdn.virtualisation.libvirtd.persist.usrData = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = ''
          The data directories this aspect wants on persistent storage, relative to the home
          directory. The consumer wires the list into its own persistence option.
        '';
      };

      config = lib.mkMerge [
        {
          kdn.virtualisation.libvirtd.persist.usrData = [
            ".local/share/images"
          ];
        }
        (lib.mkIf (cfg.windowsDrivers != null) {
          home.file.".local/share/images/virtio-win".source = cfg.windowsDrivers;
        })
      ];
    };
}
