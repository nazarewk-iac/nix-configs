{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.bn;
in {
  options.kdn.profile.user.bn = {
    enable = lib.mkEnableOption "enable bn's user profiles";
  };

  config = lib.mkIf cfg.enable {
    kdn.hw.yubikey.appId = "pam://kdn";
    nix.settings.allowed-users = ["bn"];
    kdn.programs.atuin.users = ["bn"];
    kdn.disks.users.bn.homeLocation = "usr/data";
    users.users.bn.initialHashedPassword = "$6$rounds=4096$KyC.856JV99or3zx$X2wYf1M6rO3xqDkOlMwFaAJvgiIUewc/LtWEPNCgZUBQceFlNsgEw1IgZmjduFE41IFdJWKqKuroUAznvE0Sx0";
    users.users.bn = {
      uid = 27748;
      description = "Beata";
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
    home-manager.users.bn = {
      kdn.profile.user.bn = {
        enable = true;
        osConfig = config.users.users.bn;
      };
    };
  };
}
