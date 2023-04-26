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
    kdn.profile.machine.desktop.enable = true;
    kdn.desktop.kde.enable = true;
    kdn.profile.user.sn.enable = true;
    kdn.profile.hardware.dell-e5470.enable = true;

    services.teamviewer.enable = true;
    services.xserver.displayManager.sddm.settings = {
      Autologin = {
        Session = "plasma.desktop";
        User = "sn";
      };
    };

    kdn.locale = {
      primary = "pl_PL.UTF-8";
      time = "pl_PL.UTF-8";
    };

    kdn.filesystems.disko.luks-zfs.enable = true;
    disko.devices = import ./disko.nix { inherit lib config; };
  };
}
