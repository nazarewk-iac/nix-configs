{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
    cfg = config.kdn.programs.beeper;
in {
  options.kdn.programs.beeper = {
      enable = lib.mkEnableOption "beeper messenger setup";
    };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.beeper = lib.mkDefault cfg;}];})
    (lib.optionalAttrs (kdnConfig.util.hasParentOfAnyType ["nixos"]) (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.apps."beeper" = {
            enable = true;
            dirs.cache = [];
            dirs.config = ["Beeper"];
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
