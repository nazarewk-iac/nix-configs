{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.virtualisation.containers.distrobox;
in
{
  options.kdn.virtualisation.containers.distrobox = {
    enable = lib.mkEnableOption "distrobox setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      distrobox
    ];
  };
}
