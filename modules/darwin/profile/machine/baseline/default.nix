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
      (lib.mkIf config.kdn.security.secrets.allowed {
        system.activationScripts.postActivation.text = lib.mkOrder 1501 ''
          chmod -R go+r /run/configs
        '';
      })
    ]
  );
}
