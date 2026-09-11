# The generic GPU setup, as a den aspect. It ports the `gpu` module of the old hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It turns the graphics stack on, and it holds the two hard cases of a laptop with two GPUs:
#
#   - **multi-GPU** — `supergfxd` and `switcheroo-control` switch the discrete part on and off
#   - **VFIO** — the discrete part binds to `vfio-pci` at boot, so a virtual machine claims it
#
# ## Class list: `nixos` alone
#
# The whole effect of the old module sits behind a `nixos` context guard, so the den aspect emits
# `nixos` only.
#
# ## What the port changes
#
# 1. **Two `enable` flags get a new name.** The old module holds `multiGPU.enable` and `vfio.enable`.
#    Both are reachable `kdn.*` options, so `standalone-aspects` rejects them. They become
#    `multiGPU.use` and `vfio.use`. The type, the default and the meaning do not move.
# 2. **The two sibling reads go through a `present` leaf.** The old module reads the `enable` flag of
#    the AMD GPU module and of the Intel CPU module. A den aspect has no `enable`, so each of those
#    aspects publishes a read-only `present` leaf, and this aspect reads
#    `config.kdn.hw.gpu.amd.present or false` and `config.kdn.hw.cpu.intel.present or false`. A class
#    that omits the sibling declares no such option, and the `or` then yields `false`.
# 3. **The `supergfxctl` downgrade becomes an option.** The old module carries an overlay that
#    replaces `supergfxctl` with a pinned 5.2.1 build, because 5.2.4 fails to find the discrete part
#    on one laptop. The pinned derivation lives in the deprecated tree, and an aspect must not read
#    that tree. So the aspect declares `kdn.hw.gpu.multiGPU.package` with `null` as the default, and
#    it adds the overlay only when a consumer supplies a package. The nixpkgs `supergfxd` module
#    reads `pkgs.supergfxctl` in five places and declares no `package` option, so an overlay is the
#    only route.
# 4. **The native option replaces the cross-platform package list.** A den target names its class,
#    so this one writes `environment.systemPackages`.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch. See change 1 above. `services.supergfxd.enable`
#    is a nixpkgs option, and the walk inspects the `kdn` prefix alone.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-gpu.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.gpu;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.hw.gpu.multiGPU.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          This machine holds two GPUs, so `supergfxd` and `switcheroo-control` switch between them.

          The old option is named `multiGPU.enable`. An aspect declares no reachable `enable`, so
          the name changes and nothing else does.
        '';
      };

      options.kdn.hw.gpu.multiGPU.package = lib.mkOption {
        type = lib.types.nullOr (lib.types.functionTo lib.types.package);
        default = null;
        defaultText = lib.literalExpression "null, so `pkgs.supergfxctl` stays";
        example = lib.literalExpression "prev: prev.callPackage ./supergfxctl.nix { }";
        description = ''
          A replacement `supergfxctl` package, as a function of the package set before the overlay.
          `null` keeps the nixpkgs one.

          The nixpkgs `supergfxd` module reads `pkgs.supergfxctl` in five places and declares no
          `package` option, so this aspect adds a one-attribute overlay when the value is not
          `null`.

          The type is a **function**, not a package. A package value that the consumer builds from
          its own `pkgs` would make `nixpkgs.overlays` depend on `pkgs`, and the evaluation would
          not terminate. The overlay supplies `prev`, so the function has no such cycle.

          One laptop needs a 5.2.1 build, because 5.2.4 fails to find the discrete part. See
          https://github.com/NixOS/nixpkgs/issues/355798 and
          https://gitlab.com/asus-linux/supergfxctl/-/issues/140. The pinned derivation stays with
          the consumer, because an aspect reads no file of the deprecated module tree.
        '';
      };

      options.kdn.hw.gpu.vfio.use = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Bind the discrete GPU to `vfio-pci` at boot, so a virtual machine claims it.

          The old option is named `vfio.enable`. An aspect declares no reachable `enable`, so the
          name changes and nothing else does.
        '';
      };

      options.kdn.hw.gpu.vfio.gpuIDs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "1002:1478" ];
        description = ''
          The PCI vendor and device ids `vfio-pci` claims, in `<vendor>:<device>` form. An empty
          list adds no `vfio-pci.ids` kernel parameter.
        '';
      };

      options.kdn.hw.gpu.supergfxd.mode = lib.mkOption {
        type = lib.types.enum [
          null
          "Integrated"
          "Hybrid"
          "VFIO"
        ];
        default = null;
        example = "Integrated";
        description = ''
          The `supergfxd` mode this machine boots in. `null` leaves the mode to `supergfxd`.
        '';
      };

      config = lib.mkMerge [
        {
          environment.systemPackages = filterPackages [ pkgs.nvtopPackages.full ];

          hardware.graphics.enable = true;
          hardware.graphics.enable32Bit = true;
        }
        (lib.mkIf cfg.multiGPU.use {
          environment.systemPackages = filterPackages [ pkgs.supergfxctl ];

          services.supergfxd.enable = true;
          services.switcherooControl.enable = true;

          nixpkgs.overlays = lib.optional (cfg.multiGPU.package != null) (
            _final: prev: { supergfxctl = cfg.multiGPU.package prev; }
          );

          boot.kernelParams = lib.lists.optional (
            (config.kdn.hw.gpu.amd.present or false) && cfg.supergfxd.mode != null
          ) "supergfxd.mode=${cfg.supergfxd.mode}";

          services.supergfxd.settings = {
            mode = lib.mkIf (cfg.supergfxd.mode != null) cfg.supergfxd.mode;
            always_reboot = false;
            no_logind = true;
            logout_timeout_s = 180;

            vfio_enable = lib.mkDefault false;
            vfio_save = lib.mkDefault false;
            hotplug_type = lib.mkDefault "None";
          };
        })
        (lib.mkIf cfg.vfio.use {
          # The option's own `default = null` sits at priority 1500, so `lib.mkDefault` (1000) wins
          # here and a consumer value (100) still wins over both.
          kdn.hw.gpu.supergfxd.mode = lib.mkDefault "Integrated";

          services.supergfxd.settings = {
            vfio_enable = true;
            vfio_save = true;
          };

          # See https://astrid.tech/2022/09/22/0/nixos-gpu-vfio/
          boot.initrd.kernelModules = [
            "vfio_pci"
            "vfio"
            "vfio_iommu_type1"
            # `vfio_virqfd` is part of the kernel from 6.2 on.
          ];

          # See https://gist.github.com/k-amin07/47cb06e4598e0c81f2b42904c6909329
          boot.extraModprobeConfig = ''
            softdep amdgpu pre: vfio-pci
            softdep snd_hda_intel pre: vfio-pci
          '';

          boot.kernelParams = lib.concatLists [
            # See https://docs.kernel.org/admin-guide/kernel-parameters.html
            # An AMD part turns `amd_iommu` on by default, so only Intel needs the parameter.
            (lib.lists.optional (config.kdn.hw.cpu.intel.present or false) "intel_iommu=on")
            [ "iommu=pt" ]
            (lib.lists.optional (cfg.vfio.gpuIDs != [ ]) (
              "vfio-pci.ids=" + lib.concatStringsSep "," cfg.vfio.gpuIDs
            ))
          ];
        })
      ];
    };
}
