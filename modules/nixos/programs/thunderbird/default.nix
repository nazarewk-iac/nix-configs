{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.thunderbird;
in {
  options.kdn.programs.thunderbird = {
    enable = lib.mkEnableOption "thunderbird setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.programs.thunderbird.enable = true;}];}
  ]);
}
