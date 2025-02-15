{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.profile.machine.workstation;
in {
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };
}
