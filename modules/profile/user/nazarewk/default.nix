{ lib, config, ... }:
let
  sshKeys = [
    "ssh-rsa ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAYEAvM4y0G5vZ2OYlSeGn2w7y/s+VZMzhGGb9rlUkDtWtwvsE2TWlApFyHggn6qObmQ5DUOu0Mhy6l/ojylyp2Q/C7FMoQWkeBorLKvxf8KFE1lJktCXCxJyptDn8kkNi6Fxszig/flrp5lSWWjDCafyVeyFhvMo22fblzjPOG//wu0+RnOLn9eiWC2CUvJjG11AH+AxWI4UMXY93gq5K1YVLd3EmhI/L1ITAoY3cXoheP0TW9epqe0Zq6lGO+gLiYeWgZJiolSqcHCkTzopbkIZ2cP+yEdeJrYp8ibdO7H0oyXOy48yPElkEobcISzQmTayXQfXyr9YzFPGdM0ZxxKPfpmMox2DTL+mpo1etLOf7ihJNBoR6aAcAWeYLdfqmIlWnVVySW1RPcq31tR4uCP6jpDsbEArXP7lttkWzb0EuBRKN94OVsl7gHuqSSdnrWJwU6jn8EAi9krRQtOKUrz62nOmAkWIe/4fM/3CVjuOgTSUkmuu15SgrbN9aLYp0ct/ nazarewk.id_rsa"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
  ];

  cfg = config.kdn.profile.user.nazarewk;
in
{
  options.kdn.profile.user.nazarewk = {
    enable = lib.mkEnableOption "enable nazarewk user profile";
  };

  config = lib.mkIf cfg.enable {
    users.users.nazarewk = {
      description = "Krzysztof Nazarewski";
      uid = 1000;
      isNormalUser = true;
      extraGroups = lib.filter (group: lib.hasAttr group config.users.groups) [
        "adbusers"
        "audio"
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
        "video"
        "wheel"
      ];

      openssh.authorizedKeys.keys = sshKeys;
    };

    home-manager.users.nazarewk = { kdn.profile.user.nazarewk.enable = true; };
  };
}
