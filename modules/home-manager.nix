{
  config,
  lib,
  inputs,
  ...
}: {
  home-manager.backupFileExtension = "hmbackup";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {osConfig = config;};
  home-manager.sharedModules =
    [
      ({osConfig, ...}: {
        imports = [
          inputs.impermanence.nixosModules.home-manager.impermanence
          inputs.sops-nix.homeManagerModules.sops
        ];
        config = {
          # remove  when sd-switch issues are resolved: https://github.com/nix-community/home-manager/issues/6191
          systemd.user.startServices = "suggest";
          home.enableNixpkgsReleaseCheck = true;

          xdg.enable = true;

          xdg.configFile."nix/nix.nix".text = ""; # don't allow overriding
          nixpkgs.config = lib.mkIf (!osConfig.home-manager.useGlobalPkgs) osConfig.nixpkgs.config;
          xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty {} osConfig.nixpkgs.config;
          home.file.".nixpkgs/config.nix".text = lib.generators.toPretty {} osConfig.nixpkgs.config;
        };
      })
    ]
    ++ lib.trivial.pipe ./. [
      # find all hm.nix files
      lib.filesystem.listFilesRecursive
      (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path))))
    ];
}
