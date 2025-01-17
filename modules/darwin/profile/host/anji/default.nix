{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.kdn.profile.host.anji;
in {
  options.kdn.profile.host.anji = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = config.networking.hostName == "anji";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      nixpkgs.hostPlatform = {
        config = "aarch64-apple-darwin";
        system = "aarch64-darwin";
      };

      system.stateVersion = 5;
    }
  ]);
}
