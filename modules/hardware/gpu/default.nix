{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.gpu;
in
{
  options.kdn.hardware.gpu = {
    enable = lib.mkEnableOption "common GPU setup";
  };

  config = lib.mkIf cfg.enable {
    services.supergfxd.enable = true;
    systemd.services.supergfxd.path = [ pkgs.kmod ];
    environment.systemPackages = with pkgs; [
      asusctl
      supergfxctl
    ];
  };
}
