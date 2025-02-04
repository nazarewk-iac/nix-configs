{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkMerge [
    {
      kdn.hostName = "faro";
      kdn.profile.host."${config.kdn.hostName}".enable = true;

      system.stateVersion = "25.05";
      home-manager.sharedModules = [{home.stateVersion = "25.05";}];
      networking.hostId = "4b2dd30f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      virtualisation = {
        darwin-builder = let
          GBtoMB = 1024;
          MBtoB = 1024 * 1024;
        in rec {
          workingDirectory = "/var/lib/darwin-builder";
          # those are in megabytes
          diskSize = 128 * GBtoMB;
          memorySize = 14 * GBtoMB;
          # those are in bytes
          min-free = builtins.floor (0.2 * diskSize * MBtoB);
          max-free = builtins.floor (0.8 * diskSize * MBtoB);
        };
        cores = 7;
      };
    }
  ];
}
