{
  lib,
  config,
  pkgs,
  kdnConfig,
  osConfig ? {},
  darwinConfig ? {},
  ...
}: let
  inherit (kdnConfig) inputs;

  cfg = config.kdn;

  parentConfig = let
    ensure = val:
      if builtins.isAttrs val
      then val
      else {};
  in
    ensure osConfig // ensure darwinConfig;
in {
  imports =
    [
      ../universal
      inputs.sops-nix.homeManagerModules.sops
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      suffixes = ["/default.nix"];
    };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # remove  when sd-switch issues are resolved: https://github.com/nix-community/home-manager/issues/6191
        systemd.user.startServices = "suggest";
        home.enableNixpkgsReleaseCheck = true;

        xdg.enable = true;

        nixpkgs.config =
          if parentConfig.nixpkgs.config or {} == {}
          then cfg.nixConfig.nixpkgs.config
          else parentConfig.nixpkgs.config;
        nixpkgs.overlays =
          lib.flip lib.pipe
          [
            lib.lists.unique
          ]
          (
            if parentConfig.nixpkgs.overlays or [] == []
            then cfg.nixConfig.nixpkgs.overlays
            else parentConfig.nixpkgs.overlays
          );
        xdg.configFile."nix/nix.nix".text = ""; # don't allow overriding
        xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty {} cfg.nixConfig.nixpkgs.config;
        home.file.".nixpkgs/config.nix".text = lib.generators.toPretty {} cfg.nixConfig.nixpkgs.config;
      }
    ]
  );
}
