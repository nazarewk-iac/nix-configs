{
  config,
  lib,
  inputs,
  ...
}: {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {osConfig = config;};
  home-manager.sharedModules =
    [
      {
        imports = [
          inputs.impermanence.nixosModules.home-manager.impermanence
          inputs.sops-nix.homeManagerModules.sops
        ];
        config = {
          home.enableNixpkgsReleaseCheck = true;
          xdg.enable = true;

          xdg.configFile."nix/nix.nix".text = ""; # don't allow overriding
          nixpkgs.config = config.nixpkgs.config;
          xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty {} config.nixpkgs.config;
          home.file.".nixpkgs/config.nix".text = lib.generators.toPretty {} config.nixpkgs.config;
        };
      }
    ]
    ++ lib.trivial.pipe ./. [
      # find all hm.nix files
      lib.filesystem.listFilesRecursive
      (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path))))
    ];
}
