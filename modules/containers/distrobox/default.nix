{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.containers.distrobox;
in
{
  options.kdn.containers.distrobox = {
    enable = lib.mkEnableOption "distrobox setup";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      distrobox
    ];
  };
}
