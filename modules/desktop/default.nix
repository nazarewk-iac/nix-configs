{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.desktop;
in {
  options.kdn.desktop.enable = lib.mkOption {
    type = with lib.types; bool;
    default = false;
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.desktop.enable = cfg.enable;}];}
  ]);
}
