{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.darwin.apps-fix;
in {
  config = lib.mkIf cfg.enable {
    system.activationScripts.applications.text = lib.mkForce cfg.copyScript;
  };
}
