{
  config,
  lib,
  pkgs,
  osConfig ? { },
  darwinConfig ? { },
  ...
}:
let
  cfg = config.kdn;

  parentConfig =
    let
      ensure = val: if builtins.isAttrs val then val else { };
    in
    ensure osConfig // ensure darwinConfig;
in
{
  config = lib.mkIf cfg.enable {
    # remove  when sd-switch issues are resolved: https://github.com/nix-community/home-manager/issues/6191
    systemd.user.startServices = "suggest";
    home.enableNixpkgsReleaseCheck = true;

    xdg.enable = true;

    # When the OS pins `nixpkgs.pkgs` and sets `home-manager.useGlobalPkgs`, home-manager forbids
    # any `nixpkgs.*` definition here (assertion "nixpkgs options are disabled when
    # home-manager.useGlobalPkgs is enabled"), and the users already ride on the pinned system
    # pkgs (which carry every overlay). So define them only when NOT using the global pkgs.
    nixpkgs.config = lib.mkIf (!(parentConfig.home-manager.useGlobalPkgs or false)) (
      if parentConfig.nixpkgs.config or { } == { } then
        cfg.nixConfig.nixpkgs.config
      else
        parentConfig.nixpkgs.config
    );
    nixpkgs.overlays = lib.mkIf (!(parentConfig.home-manager.useGlobalPkgs or false)) (
      lib.flip lib.pipe
        [
          lib.lists.unique
        ]
        (
          if parentConfig.nixpkgs.overlays or [ ] == [ ] then
            (cfg.nixConfig.nixpkgs.overlays or [ ])
          else
            parentConfig.nixpkgs.overlays
        )
    );
    xdg.configFile."nix/nix.nix".text = ""; # don't allow overriding
    xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty { } cfg.nixConfig.nixpkgs.config;
    home.file.".nixpkgs/config.nix".text = lib.generators.toPretty { } cfg.nixConfig.nixpkgs.config;
  };
}
