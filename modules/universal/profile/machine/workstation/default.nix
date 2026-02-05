{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.workstation;
in {
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.profile.machine.workstation.enable = true;}];})
    {
      kdn.toolset.diagrams.enable = true;
      kdn.services.k8s.management.enable = true;
    }
  ]);
}
