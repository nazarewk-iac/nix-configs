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
  options.kdn.development.db = {
    enable = lib.mkEnableOption "SQL development and access";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      duckdb # read many different files as databases
      usql # universal DB client
    ];
  };
}
