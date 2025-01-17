{
  config,
  lib,
  inputs,
  self,
  ...
}: {
  imports =
    [
      ../shared/all
      ../shared/darwin-nixos
      ./ascii-workaround.nix
      ./stylix.nix
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.lanzaboote.nixosModules.lanzaboote
      inputs.lanzaboote.nixosModules.uki
      inputs.lix-module.nixosModules.default
      inputs.nur.modules.nixos.default
      inputs.preservation.nixosModules.preservation
      inputs.sops-nix.nixosModules.sops
    ]
    ++ lib.trivial.pipe ./. [
      lib.filesystem.listFilesRecursive
      # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];

  config = lib.mkIf config.kdn.enable (lib.mkMerge [
    {
      # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
      disko.enableConfig = lib.mkDefault false;
    }
    {
      home-manager.backupFileExtension = "hmbackup";
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = {
        inherit self inputs;
      };
      home-manager.sharedModules = [
        {
          imports =
            [../home-manager]
            ++ lib.trivial.pipe ./. [
              # find all hm.nix files
              lib.filesystem.listFilesRecursive
              (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path))))
            ];
        }
      ];
    }
  ]);
}
