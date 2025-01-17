{
  config,
  lib,
  pkgs,
  inputs,
  self,
  ...
}: let
  cfg = config.kdn;
in {
  imports =
    [
      ../universal
      # this is very simple, works for both NixOS and darwin
      inputs.lix-module.nixosModules.default
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  config = lib.mkIf config.kdn.enable (lib.mkMerge [
    {
      nix.registry.nixpkgs.flake = inputs.nixpkgs;
      nix.optimise.automatic = true;
      nix.package = pkgs.lix;
      nixpkgs.overlays = [self.overlays.default];
    }
    {
      nix.extraOptions = cfg.nixConfig.nix.extraOptions;
      nix.settings = cfg.nixConfig.nix.settings;
      nixpkgs.config = cfg.nixConfig.nixpkgs.config;
    }
    {
      home-manager.backupFileExtension = "hmbackup";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {inherit self inputs;};
      home-manager.sharedModules = [{imports = [./hm.nix];}];
    }
  ]);
}
