{
  lib,
  config,
  pkgs,
  self,
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
      nix.linux-builder.package = pkgs.darwin.linux-builder.override (old: {
        modules =
          old.modules
          ++ [
            self.nixosModules.default
            (import ./faro.nix)
          ];
      });
    })
  ]);
}
