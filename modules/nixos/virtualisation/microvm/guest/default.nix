{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.virtualisation.microvm.guest;

  microvmPersistNames = ["microvm"] ++ builtins.attrNames config.kdn.disks.base;
in {
  imports = kdnConfig.self.lib.lists.optionals (!kdnConfig.features.microvm-guest) [
    kdnConfig.inputs.microvm.nixosModules.microvm-options
  ];

  options.kdn.virtualisation.microvm.guest = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = kdnConfig.features.microvm-guest;
    };
  };

  config = lib.mkMerge [
    # `microvm.guest.enable` defaults to `true`
    {microvm.guest.enable = cfg.enable;}
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.profile.machine.baseline.enable = lib.mkDefault true;
          security.sudo.wheelNeedsPassword = lib.mkDefault false;
        }
        {
          microvm.shares = [
            {
              # shared /nix/store
              proto = "virtiofs";
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
        }
        {
          preservation.enable = true;
          preservation.preserveAt."microvm".persistentStoragePath = "/nix/persist/microvm";
          preservation.preserveAt."microvm".directories = [
            {
              directory = "/var/log/journal";
              inInitrd = true;
            }
          ];
          preservation.preserveAt."microvm".files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
              how = "symlink";
              configureParent = true;
            }
            {
              file = "/etc/ssh/ssh_host_ed25519_key";
              how = "symlink";
              mode = "0600";
              inInitrd = true;
            }
            {
              file = "/etc/ssh/ssh_host_rsa_key";
              how = "symlink";
              mode = "0600";
              inInitrd = true;
            }
          ];
          microvm.shares = lib.pipe config.preservation.preserveAt [
            (lib.attrsets.mapAttrsToList (
              persistName: preserveAtCfg: {
                source = "/var/lib/microvms-persist/${config.kdn.hostName}/${persistName}";
                mountPoint = preserveAtCfg.persistentStoragePath;
                tag = "microvm-persist-${persistName}";
                proto = "virtiofs";
              }
            ))
          ];
        }
      ]
    ))
  ];
}
