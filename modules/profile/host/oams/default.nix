{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.workstation.enable = true;
    kdn.hardware.gpu.amd.enable = true;
  };
}
