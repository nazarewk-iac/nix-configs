{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.cloud;
in
{
  options.kdn.development.cloud = {
    enable = lib.mkEnableOption "cloud development";
  };

  config = lib.mkIf cfg.enable {
    kdn.development.nodejs.enable = lib.mkDefault true;
    kdn.development.lua.enable = lib.mkDefault true;

    kdn.env.packages = with pkgs; [
      redis
    ];
  };
}
