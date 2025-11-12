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
      withDefault = true;
    };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {
        networking.hostName = cfg.hostName;
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
        nix.optimise.automatic = true;
        nix.package = pkgs.lixPackageSets.latest.lix;
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
