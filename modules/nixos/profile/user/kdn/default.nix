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
      kdn.hardware.yubikey.appId = "pam://kdn";
      users.users.kdn.initialHashedPassword = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
      users.users.kdn = {
        linger = true;
        uid = 31893;
        subUidRanges = [
          {
            count = 65536;
            startUid = 100000;
          }
        ];
        subGidRanges = [
          {
            count = 65536;
            startGid = 100000;
          }
        ];
        description = "Krzysztof Nazarewski";
        isNormalUser = true;
        openssh.authorizedKeys.keys = cfg.ssh.authorizedKeysList;
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

      kdn.virtualization.libvirtd.lookingGlass.instances = {kdn-default = "kdn";};

      networking.firewall = {
        # syncthing ranges
        allowedTCPPorts = [22000];
        allowedUDPPorts = [21027 22000];
      };
    }
    (
      let
        cfg = {
          programs.gpg.publicKeys = [
            {
              source = ./gpg-pubkeys.txt;
              trust = "ultimate";
            }
          ];
        };
      in {
        home-manager.users.root = cfg;
        home-manager.users.kdn = cfg;
      }
    )
    {
      home-manager.users.kdn.kdn.profile.user.kdn.enable = true;
      home-manager.users.kdn.kdn.profile.user.kdn.osConfig = config.users.users.kdn;
    }
  ]);
}
