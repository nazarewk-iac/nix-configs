{ config, pkgs, lib, modulesPath, waylandPkgs, ... }:
# Dell Latitude E5470
let
  cfg = config.kdn.profile.host.obler;
in
{
  options.kdn.profile.host.obler = {
    enable = lib.mkEnableOption "enable obler host profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.basic.enable = true;
    kdn.profile.user.sn.enable = true;

    system.stateVersion = "23.05";
    networking.hostId = "f6345d38"; # cut -c-8 </proc/sys/kernel/random/uuid
    networking.hostName = "obler";
  };
}
