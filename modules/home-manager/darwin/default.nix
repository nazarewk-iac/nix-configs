{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.darwin;
in
{
  config = lib.mkIf cfg.enable {
    kdn.darwin = {
      dirs.apps.src = "$newGenPath/home-path/Applications";
      dirs.apps.base = "${config.home.homeDirectory}/Applications/Home Manager Apps";
    };
  };
}
