{
  config,
  lib,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) inputs;
in {
  imports =
    [
      ../shared/universal
      ../shared/darwin-nixos-os
      ./ascii-workaround.nix
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.lanzaboote.nixosModules.lanzaboote
      inputs.nur.modules.nixos.default
      inputs.preservation.nixosModules.preservation
      inputs.sops-nix.nixosModules.sops
      inputs.angrr.nixosModules.angrr
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {
        # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
        disko.enableConfig = lib.mkDefault false;
      }
      {
        home-manager.sharedModules = [{imports = [./hm.nix];}];
      }
    ]
  );
}
