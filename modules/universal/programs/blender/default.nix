{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
    cfg = config.kdn.programs.blender;
in {
  options.kdn.programs.blender = {
      enable = lib.mkEnableOption "blender setup";
    };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.blender = lib.mkDefault cfg;}];})
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.apps.blender = {
            enable = true;
            dirs.cache = ["blender"];
            dirs.config = ["blender"];
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
