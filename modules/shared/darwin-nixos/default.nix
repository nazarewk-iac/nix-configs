{
  config,
  lib,
  pkgs,
  kdnConfig,
  ...
} @ args: let
  inherit (kdnConfig) self inputs;
  cfg = config.kdn;
in {
  imports =
    [
      ../../universal
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      suffixes = ["/default.nix"];
    };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {
        networking.hostName = cfg.hostName;
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
        nix.optimise.automatic = true;
        nix.package = let
          latest = pkgs.lixPackageSets.latest.lix;
        in
          # TODO: 2025-12-19: lix 2.94.0 failed tests on darwin
          if pkgs.stdenv.hostPlatform.isDarwin
          then
            latest.overrideAttrs (prev: {
              doCheck = false;
              doInstallCheck = false;
            })
          else latest;
        nixpkgs.overlays = [self.overlays.default];
      }
      (lib.mkIf (!kdnConfig.features.microvm-guest) {
        nix.extraOptions = cfg.nixConfig.nix.extraOptions;
        nix.settings = cfg.nixConfig.nix.settings;
        nixpkgs.config = cfg.nixConfig.nixpkgs.config;
      })
      {
        home-manager.backupFileExtension = "hmbackup";
        home-manager.useGlobalPkgs = false;
        home-manager.useUserPackages = true;

        home-manager.sharedModules = [
          ({kdnConfig, ...}: {
            imports = kdnConfig.util.loadModules {
              curFile = ./default.nix;
              src = ./.;
              suffixes = ["/hm.nix"];
            };
          })
          {
            config = {
              kdn.hostName = cfg.hostName;
            };
          }
        ];
      }
    ]
  );
}
