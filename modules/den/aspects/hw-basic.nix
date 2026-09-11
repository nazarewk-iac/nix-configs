# The hardware discovery tool set, as a den aspect. It ports the `basic` module of the old
# hardware area.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It installs the tools that answer one question: what hardware does this machine hold? The list
# covers DMI, PCI, USB, sysfs, sensors, Vulkan and a load generator.
#
# ## Class list: `nixos` alone
#
# The old module puts every package behind a `nixos` context guard. One line sits outside that
# guard, and it forwards a tool-set flag; see change 2 below. So the den aspect emits `nixos` only.
#
# ## What the port changes
#
# 1. **The four discovery scripts become an option.** The old module builds them from four `.sh`
#    files that live next to it, in the deprecated tree. An aspect must not read that tree, so the
#    aspect declares `kdn.hw.basic.discoveryScripts` instead and defaults it to the empty list. A
#    consumer that wants the scripts passes them. The scripts move to `hack/` in a later step, and
#    the default then reads them by relative path, exactly as the `jj-fork` aspect reads
#    `hack/pre-push.sh`.
# 2. **The tool-set forward-write goes.** The old module writes a `unix` tool-set flag with
#    `lib.mkDefault true`. An aspect has no `enable`, so a den consumer includes the tool-set
#    aspect itself.
# 3. **The native option replaces the cross-platform package list.** A den target names its class,
#    so this one writes `environment.systemPackages`. The `apply` filter of the old option moves to
#    ../common/filter-packages.nix, and the call below opts in per list.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module below takes `config`, `lib` and `pkgs` only.
{ ... }:
{
  kdn.hw-basic.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.hw.basic;

      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      options.kdn.hw.basic.discoveryScripts = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression ''
          [ (pkgs.writeShellApplication { name = "lsiommu"; text = "…"; }) ]
        '';
        description = ''
          Extra hardware discovery scripts this machine installs.

          The old module builds four such scripts from `.sh` files that sit in the deprecated
          module tree. An aspect must not read that tree, so the default is the empty list. A
          consumer passes its own scripts here.
        '';
      };

      config.environment.systemPackages = filterPackages (
        (with pkgs; [
          dmidecode
          # `glxinfo` moved into this package.
          mesa-demos
        ])
        # `hardinfo` left nixpkgs in 2025; `hardinfo2` replaces it, and it builds on x86 only.
        ++ lib.lists.optionals (with pkgs.stdenv.hostPlatform; isLinux && isx86_64) [
          pkgs.hardinfo2
        ]
        ++ (with pkgs; [
          hddtemp
          # About 560 MiB, measured 2024-06-25.
          hw-probe
          inxi
          lm_sensors
          lshw
          lsof
          # lspci
          pciutils
          # systool
          sysfsutils
          # lsusb
          usbutils

          vulkan-caps-viewer
          vulkan-tools

          stress-ng
        ])
        ++ cfg.discoveryScripts
      );
    };
}
