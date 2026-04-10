{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
    cfg = config.kdn.programs.chrome;
in {
  options.kdn.programs.chrome = {
      enable = lib.mkEnableOption "Google Chrome setup";
    };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.chrome = lib.mkDefault cfg;}];})
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.apps.chrome = {
            enable = true;
            package.original = pkgs.google-chrome;
            dirs.cache = [];
            dirs.config = ["google-chrome"];
            dirs.data = [];
            dirs.disposable = [];
            dirs.reproducible = [];
            dirs.state = [];
          };
        }
      ]
    )))
  ];
}
