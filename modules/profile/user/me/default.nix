{ lib, config, ... }:
let
  cfg = config.kdn.profile.user.kdn;
in
{
  options.kdn.profile.user.kdn = {
    enable = lib.mkEnableOption "enable my user profiles";
    ssh = lib.mkOption {
      readOnly = true;
      default = import ./ssh.nix { inherit lib; };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # required for remote-building using nixinate, see https://discourse.nixos.org/t/way-to-build-nixos-on-x86-64-machine-and-serve-to-aarch64-over-local-network/18660
      # TODO: switch to signed store building?
      nix.settings.trusted-users = [ "kdn" ];
      kdn.programs.atuin.users = [ "kdn" ];
      kdn.hardware.yubikey.appId = "pam://kdn";
      users.users.kdn.initialHashedPassword = "$y$j9T$yl3J5zGJ5Yq8c6fXMGxNk.$XE3X8aWpD3FeakMBD/fUmCExXMuy7B6tm7ZECmuxpF4";
      users.users.kdn = {
        uid = 31893;
        subUidRanges = [{ count = 65536; startUid = 100000; }];
        subGidRanges = [{ count = 65536; startGid = 100000; }];
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
          "power"
          "podman"
          "scanner"
          "tty"
          "ydotool"
          "video"
          "weechat"
          "wheel"
        ];
      };

      kdn.virtualization.libvirtd.lookingGlass.instances = { kdn-default = "kdn"; };
      home-manager.users.kdn = {
        kdn.profile.user.kdn = {
          enable = true;
          osConfig = config.users.users.kdn;
        };
      };

      networking.firewall = {
        # syncthing ranges
        allowedTCPPorts = [ 22000 ];
        allowedUDPPorts = [ 21027 22000 ];
      };
    }
    (lib.mkIf config.kdn.headless.enableGUI {
      networking.firewall = let kdeConnectRange = [{ from = 1714; to = 1764; }]; in {
        allowedTCPPortRanges = kdeConnectRange;
        allowedUDPPortRanges = kdeConnectRange;
      };
    })
  ]);
}
