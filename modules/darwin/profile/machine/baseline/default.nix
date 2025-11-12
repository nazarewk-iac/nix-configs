{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {home-manager.sharedModules = [{kdn.profile.machine.baseline.enable = true;}];}
    ]
  );
}
