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
      ../universal
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

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
        home-manager.extraSpecialArgs = kdnConfig.output.mkSubmodule {moduleType = "home-manager";};

        home-manager.sharedModules = [
          {
            imports = [./hm.nix];
            config = {
              kdn.hostName = cfg.hostName;
            };
          }
        ];
      }
    ]
  );
}
