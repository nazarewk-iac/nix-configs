{ lib, pkgs, config, system, ... }:
let
  cfg = config.kdn.development.db.mysql;
in
{
  options.kdn.development.db.mysql = {
    enable = lib.mkEnableOption "SQL development and access";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      usql # universal DB client
    ];
  };
}
