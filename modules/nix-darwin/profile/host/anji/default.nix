{
  lib,
  config,
  pkgs,
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
      environment.systemPackages = with pkgs; [
        utm
      ];
    }
  ]);
}
