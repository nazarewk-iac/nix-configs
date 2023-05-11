{ lib, config, ... }:
let
  cfg = config.kdn.profile.user.me;
in
{
  options.kdn.profile.user.me = {
    enable = lib.mkEnableOption "enable my user profiles";
    ssh = lib.mkOption {
      readOnly = true;
      default = import ./ssh.nix { inherit lib; };
    };
  };

  config = lib.mkIf cfg.enable ({
    # required for remote-building using nixinate, see https://discourse.nixos.org/t/way-to-build-nixos-on-x86-64-machine-and-serve-to-aarch64-over-local-network/18660
    # TODO: switch to signed store building?
    nix.settings.trusted-users = [ "kdn" ];
    kdn.hardware.yubikey.appId = "pam://kdn";

    users.users.kdn = {
      uid = 31893;
      description = "Krzysztof Nazarewski";
      isNormalUser = true;
      createHome = true; # makes sure ZFS mountpoints are properly owned?
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
        "wheel"
      ];
    };

    kdn.virtualization.libvirtd.lookingGlass.instances = { kdn-default = "kdn"; };
    home-manager.users.kdn = { kdn.profile.user.me.nixosConfig = config.users.users.kdn; };

    networking.firewall = let kdeConnectRange = [{ from = 1714; to = 1764; }]; in {
      allowedTCPPortRanges = kdeConnectRange;
      allowedUDPPortRanges = kdeConnectRange;
      # syncthing ranges
      allowedTCPPorts = [ 22000 ];
      allowedUDPPorts = [ 21027 22000 ];
    };
    nixpkgs.config.firefox.enablePlasmaBrowserIntegration = true;
  });
}
