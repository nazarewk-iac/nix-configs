{
  lib,
  config,
  ...
}: let
  cfg = config.kdn.profile.user.kdn;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # TODO: switch to signed store building?
      nix.settings.trusted-users = ["kdn"];
      kdn.programs.atuin.users = ["kdn"];
      kdn.programs.atuin.autologinUsers = ["kdn"];
      kdn.hw.yubikey.appId = "pam://kdn";
      users.users.kdn.initialHashedPassword = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
      users.users.kdn = {
        linger = true;
        uid = 31893;
        # this is handled by a script near `services.userborn.enable = true;`
        isNormalUser = true;
        extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
          "adbusers"
          "audio"
          "deluge"
          "dialout"
          "docker"
          "kvm"
          "libvirtd"
          "lp"
          "mlocate"
          "networkmanager"
          "pipewire"
          "plugdev"
          "podman"
          "power"
          "scanner"
          "tty"
          "video"
          "weechat"
          "wheel"
          "wireshark"
          "ydotool"
        ];
      };

      networking.firewall = {
        # syncthing ranges
        allowedTCPPorts = [22000];
        allowedUDPPorts = [21027 22000];
      };
    }
    {
      home-manager.users.kdn.kdn.profile.user.kdn.enable = true;
      home-manager.users.root.programs.gpg.publicKeys = [
        {
          source = cfg.gpg.publicKeys;
          trust = "ultimate";
        }
      ];
    }
    {
      kdn.networking.netbird.adminUsers = ["kdn"];
    }
  ]);
}
