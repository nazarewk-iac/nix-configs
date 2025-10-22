{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.darwin;
in {
  config = lib.mkIf cfg.enable {
    kdn.darwin = {
      dirs.apps.src = config.system.build.applications + /Applications;
      dirs.apps.base = "/Applications/Nix Apps";
    };
  };
}
