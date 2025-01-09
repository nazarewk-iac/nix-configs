{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.kdeconnect;
in {
  options.kdn.programs.kdeconnect = {
    enable = lib.mkEnableOption "kdeconnect setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {home-manager.sharedModules = [{kdn.programs.kdeconnect.enable = true;}];}
    {
      # takes care of firewall
      programs.kdeconnect.enable = true;
    }
  ]);
}
