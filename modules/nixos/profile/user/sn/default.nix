{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.sn;
in {
  options.kdn.profile.user.sn = {
    enable = lib.mkEnableOption "enable sn's user profiles";
  };

  config = lib.mkIf cfg.enable {
    kdn.hw.yubikey.appId = "pam://kdn";
    nix.settings.allowed-users = ["sn"];
    kdn.programs.atuin.users = ["sn"];
    kdn.hw.disks.users.sn.homeLocation = "usr/data";
    users.users.sn.initialHashedPassword = "$y$j9T$WGU0Qrlm0.jq7Y4QfyVYC0$HiYyLZMDX8M/A7WNshB5PjtZEGufQ.Qa93FY4WIlcw8";
    users.users.sn = {
      uid = 48378;
      description = "Staś";
      isNormalUser = true;
      createHome = true; # makes sure ZFS mountpoints are properly owned?
      extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
        "audio"
        "dialout"
        "lp"
        "lpadmin"
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
        osConfig = config.users.users.sn;
      };
    };
  };
}
