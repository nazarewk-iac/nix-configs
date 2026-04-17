{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers.docker;
in
{
  options.kdn.virtualisation.containers.docker = {
    enable = lib.mkEnableOption "docker daemon setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      virtualisation.docker.enable = true;

      kdn.env.packages = with pkgs; [
        docker-client
        docker-compose
      ];
    }
  );
}
