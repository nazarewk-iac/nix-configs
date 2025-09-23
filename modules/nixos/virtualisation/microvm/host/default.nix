{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  cfg = config.kdn.virtualisation.microvm.host;
in {
  imports = [kdn.inputs.microvm.nixosModules.host];

  options.kdn.virtualisation.microvm.host = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = kdn.features.microvm-host;
    };

    flake.nixpkgs = lib.mkOption {
      default = kdn.inputs.nixpkgs;
    };
    flake.microvm = lib.mkOption {
      default = kdn.inputs.microvm;
    };
  };

  config = lib.mkMerge [
    {
      # this default to `true`, so need to also pin it to false
      microvm.host.enable = cfg.enable;
    }
    (lib.mkIf cfg.enable {
      # see https://github.com/astro/microvm.nix/blob/24136ffe7bb1e504bce29b25dcd46b272cbafd9b/examples/microvms-host.nix
      nix.registry.microvm.flake = cfg.flake.microvm;

      nix.settings.trusted-public-keys = [
        "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqys="
      ];

      nix.settings.substituters = [
        # TODO: cachix.org was down on  2025-03-20 17:20
        #"https://microvm.cachix.org"
      ];
      environment.systemPackages = with cfg.flake.microvm.packages."${pkgs.stdenv.system}"; [
        microvm
      ];
      kdn.hw.disks.persist."usr/data".directories = [
        config.microvm.stateDir
      ];

      systemd.tmpfiles.rules = lib.pipe config.microvm.vms [
        builtins.attrValues
        (builtins.map (
          microVMCfg: let
            # vm.config is a NixOS module, which in turn has `.{options,config}` attributes...
            vmConfig = microVMCfg.config.config;
          in
            lib.flip lib.attrsets.mapAttrsToList vmConfig.preservation.preserveAt (
              persistName: _: "d /var/lib/microvms-persist/${vmConfig.kdn.hostName}/${persistName} 0755 root root"
            )
        ))
        lib.lists.flatten
        (builtins.sort builtins.lessThan)
        lib.lists.unique
      ];
    })
  ];
}
