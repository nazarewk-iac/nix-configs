# The `virtualisation/microvm/host` module of the old tree, as a den aspect.
#
# The old module stays in place and keeps working. This file is the parallel den implementation.
#
# ## What it does
#
# It makes the machine a microvm.nix host. It turns `microvm.host` on, registers the microvm flake
# in the local flake registry, trusts the project's binary cache, installs the `microvm` command,
# keeps the VM state directory across a reboot, and creates one directory per guest preservation
# bucket.
#
# ## What the port changes
#
# 1. **`enable` goes.** Inclusion is the switch. The old default reads a host feature flag, and den
#    has no feature set. A host that includes this aspect **is** a microvm host.
# 2. **The old module also pins `microvm.host.enable` to `false`.** It has to, because the old tree
#    imports the microvm host module for every NixOS host and that option defaults to `true`. This
#    aspect imports the module only when a host includes the aspect, so the false branch goes.
# 3. **`kdn.env.packages` goes.** The target writes `environment.systemPackages`, through
#    ../common/filter-packages.nix. Design B.
# 4. **The unused `flake.nixpkgs` option goes.** Nothing reads it.
# 5. **The empty `nix.settings.substituters` write goes.** It adds nothing.
# 6. **The guest name read falls back to `networking.hostName`.** The old module reads
#    `vmConfig.kdn.hostName` from each guest's own evaluation. A guest that an adopter builds may
#    declare no `kdn` option at all, so the read now falls back. den's `kdn.hostName` defaults to
#    `networking.hostName`, so a guest of this repository gives the same name as before.
#
# ## The state path
#
# `/var/lib/microvms-persist` is the parent of every guest share. ./virt-microvm-guest.nix holds the
# same literal, exactly as the two old modules do. The two aspects share no option, so a change
# needs an edit in both files.
#
# ## The three rules this tree holds for every aspect
#
# 1. **No entity argument.** An aspect that reads `{ host, ... }` resolves to `{ imports = [ ]; }`
#    across the export boundary, in silence.
# 2. **No `enable` option.** Inclusion is the switch.
# 3. **No custom module argument.** The target module takes `config`, `lib` and `pkgs` only.
#    `inputs` comes from this file's own scope, because the check harness passes `pkgs` alone to a
#    target.
{ inputs, ... }:
let
  declaration =
    { lib, ... }:
    {
      options.kdn.virtualisation.microvm.host.flake.microvm = lib.mkOption {
        type = lib.types.raw;
        default = inputs.microvm;
        defaultText = lib.literalExpression "inputs.microvm";
        description = ''
          The microvm.nix flake this host registers and installs the `microvm` command from.

          A consumer with a pin of its own writes that flake here.
        '';
      };
    };

  nixosTarget =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.kdn.virtualisation.microvm.host;
      filterPackages = import ../common/filter-packages.nix { inherit lib; };
    in
    {
      imports = [
        declaration
        ../common/persist.nix
        inputs.microvm.nixosModules.host
      ];

      microvm.host.enable = true;

      # It follows
      # https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/examples/microvms-host.nix
      nix.registry.microvm.flake = cfg.flake.microvm;

      nix.settings.trusted-public-keys = [
        "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
      ];

      environment.systemPackages = filterPackages (
        with cfg.flake.microvm.packages."${pkgs.stdenv.hostPlatform.system}";
        [
          microvm
        ]
      );

      kdn.disks.persist."usr/data".directories = [
        config.microvm.stateDir
      ];

      # One directory per guest preservation bucket. Each guest mounts its own bucket over virtiofs,
      # so the directory must exist on the host before the guest starts.
      systemd.tmpfiles.rules = lib.pipe config.microvm.vms [
        builtins.attrValues
        (map (
          microVMCfg:
          let
            vmConfig = microVMCfg.config.config;
            vmName = vmConfig.kdn.hostName or vmConfig.networking.hostName;
          in
          lib.flip lib.attrsets.mapAttrsToList (vmConfig.preservation.preserveAt or { }) (
            persistName: _: "d /var/lib/microvms-persist/${vmName}/${persistName} 0755 root root"
          )
        ))
        lib.lists.flatten
        (builtins.sort builtins.lessThan)
        lib.lists.unique
      ];
    };
in
{
  kdn.virt-microvm-host.nixos = nixosTarget;
}
