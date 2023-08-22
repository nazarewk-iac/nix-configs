{ lib, config, ... }:
let
  cfg = config.kdn.profile.user.sn;
in
{
  options.kdn.profile.user.sn = {
    enable = lib.mkEnableOption "enable sn's user profiles";
  };

  config = lib.mkIf cfg.enable ({
    kdn.hardware.yubikey.appId = "pam://kdn";
    users.users.sn = {
      uid = 48378;
      isNormalUser = true;
      createHome = true; # makes sure ZFS mountpoints are properly owned?
      extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
        "audio"
        "dialout"
        "lp"
        "mlocate"
        "networkmanager"
        "pipewire"
        "plugdev"
        "power"
        "scanner"
        "tty"
        "video"
      ];
    };
    home-manager.users.sn = {
      kdn.profile.user.sn = {
        enable = true;
        nixosConfig = config.users.users.sn;
      };
    };
  });
}
