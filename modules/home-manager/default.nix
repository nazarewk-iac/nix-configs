{
  lib,
  config,
  pkgs,
  inputs,
  osConfig ? {},
  darwinConfig ? {},
  ...
}: let
  cfg = config.kdn;

  parentConfig = osConfig // darwinConfig;
in {
  imports =
    [
      ../shared/universal
      inputs.sops-nix.homeManagerModules.sops
    ]
    ++ lib.trivial.pipe ./. [
      # find all hm.nix files
      lib.filesystem.listFilesRecursive
      (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
    ];
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # remove  when sd-switch issues are resolved: https://github.com/nix-community/home-manager/issues/6191
      systemd.user.startServices = "suggest";
      home.enableNixpkgsReleaseCheck = true;

      xdg.enable = true;

      xdg.configFile."nix/nix.nix".text = ""; # don't allow overriding
      nixpkgs.config = lib.mkIf (!(parentConfig.home-manager.useGlobalPkgs or false)) cfg.nixConfig.nixpkgs.config;
      xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty {} cfg.nixConfig.nixpkgs.config;
      home.file.".nixpkgs/config.nix".text = lib.generators.toPretty {} cfg.nixConfig.nixpkgs.config;
    }
    (lib.mkIf pkgs.stdenv.isDarwin {kdn.darwin.type = "home-manager";})
  ]);
}
