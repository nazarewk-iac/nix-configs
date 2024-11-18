{
  lib,
  pkgs,
  config,
  system,
  ...
}: let
  cfg = config.kdn.development.db;
in {
  options.kdn.development.documents = {
    enable = lib.mkEnableOption "documents development";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{kdn.development.documents.enable = true;}];
  };
}
