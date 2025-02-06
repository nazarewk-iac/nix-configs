{
  lib,
  config,
  pkgs,
  modulesPath,
  self,
  inputs,
  ...
}: let
  cfg = config.kdn.profile.host.anji;
in {
  options.kdn.profile.host.anji = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.kdn.hostName == "anji";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.baseline.enable = true;
    }
    {
      nixpkgs.hostPlatform = {
        config = "aarch64-apple-darwin";
        system = "aarch64-darwin";
      };

      system.stateVersion = 5;
      home-manager.sharedModules = [{home.stateVersion = "25.05";}];
    }
    {
      kdn.nix.remote-builder.enable = true;
    }
    (lib.mkIf config.kdn.nix.remote-builder.enable {
      nix.linux-builder.enable = true;
      nix.linux-builder.speedFactor = 4;
      nix.linux-builder.maxJobs = 2;
      nix.linux-builder.systems = [
        "aarch64-linux"
      ];
      nix.linux-builder.package = lib.makeOverridable (
        {modules}: let
          hostPkgs = pkgs;
          toGuest = builtins.replaceStrings ["darwin"] ["linux"];

          nixosConfiguration = lib.nixosSystem {
            # see https://github.com/NixOS/nixpkgs/blob/799ba5bffed04ced7067a91798353d360788b30d/pkgs/top-level/darwin-packages.nix#L280-L306
            system = "aarch64-linux";
            specialArgs = {
              inherit self inputs;
              inherit (self) lib;
            };
            modules =
              [
                "${inputs.nixpkgs}/nixos/modules/profiles/nix-builder-vm.nix"
                {
                  virtualisation.host.pkgs = hostPkgs;
                  nixpkgs.hostPlatform = lib.mkDefault (toGuest hostPkgs.stdenv.hostPlatform.system);
                }
                self.nixosModules.default
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
                {
                  kdn.hostName = "faro";

                  system.stateVersion = "25.05";
                  home-manager.sharedModules = [{home.stateVersion = "25.05";}];
                  networking.hostId = "4b2dd30f"; # cut -c-8 </proc/sys/kernel/random/uuid
                }
                {
                  kdn.nix.remote-builder.enable = true;
                  security.sudo.wheelNeedsPassword = false;
                }
              ]
              ++ modules;
          };
        in
          nixosConfiguration.config.system.build.macos-builder-installer
      ) {modules = [];};
    })
  ]);
}
