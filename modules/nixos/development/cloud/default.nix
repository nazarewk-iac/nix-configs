{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.cloud;
in {
  options.kdn.development.cloud = {
    enable = lib.mkEnableOption "cloud development";
  };

  config = lib.mkIf cfg.enable {
    kdn.development.nodejs.enable = true;
    kdn.development.lua.enable = true;

    environment.systemPackages = with pkgs; [
      redis
    ];
  };
}
