{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.db;
in
{
  options.kdn.development.db = {
    enable = lib.mkEnableOption "SQL development and access";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        duckdb # read many different files as databases
        # TODO: 2026-03-23: didn't build: enable after https://github.com/NixOS/nixpkgs/pull/499348
        #usql # universal DB client
      ];
    }
  );
}
