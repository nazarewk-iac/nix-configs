{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
    cfg = config.kdn.programs.rambox;
in {
  options.kdn.programs.rambox = {
      enable = lib.mkEnableOption "rambox setup";
    };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.rambox = lib.mkDefault cfg;}];})
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.apps."rambox" = {
            enable = true;
            dirs.cache = [];
            dirs.config = ["rambox"];
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
