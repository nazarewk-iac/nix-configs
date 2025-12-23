{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.darwinModules.default
  ];

  options.kdn.hosts.anji = {
    initialLinuxBuilder = lib.mkOption {
      # enable when building for the first time: needs to be pulled from cache without any customizations
      type = with lib.types; bool;
      default = false;
    };
  };

  config = lib.mkMerge [
    {
      kdn.hostName = "anji";
      kdn.profile.machine.baseline.enable = true;
    }
    {
      nixpkgs.system = "aarch64-darwin";
      system.stateVersion = 6;
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
    }
    {
      kdn.nix.remote-builder.enable = true;
      environment.systemPackages = with pkgs; [
        utm
      ];
    }
    {
      # inspired by https://nixcademy.com/posts/macos-linux-builder/
      nix.settings.trusted-users = ["@admin"];

      nix.linux-builder.enable = true;
      kdn.hosts.anji.initialLinuxBuilder = false;
      nix.linux-builder.workingDirectory = "/nixos-builder";
    }
    (lib.mkIf (!config.kdn.hosts.anji.initialLinuxBuilder) {
      nix.linux-builder.config = let
        gibs.disk = 256;
        gibs.min-free = gibs.disk / 10;
        gibs.max-free = 2 * gibs.min-free;
      in {
        # TODO: somehow add specialArgs here? not sure it's possible
        imports = [./linux-builder.nix];

        config = lib.mkMerge [
          (let
            MiB = 1;
            GiB = 1024 * MiB;
          in {
            virtualisation.darwin-builder.diskSize = gibs.disk * GiB;
            virtualisation.darwin-builder.memorySize = 12 * GiB;
            virtualisation.cores = 6;
          })
          (let
            B = 1;
            KiB = 1024 * B;
            MiB = 1024 * KiB;
            GiB = 1024 * MiB;
          in {
            virtualisation.darwin-builder.min-free = gibs.min-free * GiB;
            virtualisation.darwin-builder.max-free = gibs.max-free * GiB;
          })
        ];
      };

      nix.linux-builder.systems = ["aarch64-linux"];
      nix.linux-builder.supportedFeatures = ["kvm" "benchmark" "big-parallel"];
      nix.linux-builder.maxJobs = 4;
      nix.linux-builder.speedFactor = 8;
    })
  ];
}
