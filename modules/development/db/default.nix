{ lib, pkgs, config, system, ... }:
let
  cfg = config.kdn.development.db;
in
{
  options.kdn.development.db = {
    enable = lib.mkEnableOption "SQL development and access";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      usql # universal DB client
    ];
  };
}
