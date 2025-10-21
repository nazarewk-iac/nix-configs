{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.development.db;
in
{
  options.kdn.development.web = {
    enable = lib.mkEnableOption "web development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [ { kdn.development.web.enable = true; } ];
    kdn.development.nodejs.enable = true;
  };
}
