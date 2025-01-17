{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.darwin.apps-fix;
in {
  disabledModules = [
    "targets/darwin/linkapps.nix"
  ];

  config = lib.mkIf cfg.enable {
    home.activation.copyApplications = lib.hm.dag.entryAfter ["writeBoundary"] cfg.copyScript;
  };
}
