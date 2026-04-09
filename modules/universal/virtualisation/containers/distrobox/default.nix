{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers.distrobox;
in
{
  options.kdn.virtualisation.containers.distrobox = {
    enable = lib.mkEnableOption "distrobox setup";
  };

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        distrobox
      ];
    }
  );
}
