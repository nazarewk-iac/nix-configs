{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.ide;
in {
  options.kdn.toolset.ide = {
    enable = lib.mkEnableOption "IDEs utils";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.toolset.ide.enable = cfg.enable;}];}
  ]);
}
