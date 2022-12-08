{ lib, config, ... }:
let
  sshKeys = [
    "ssh-rsa ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAYEAvM4y0G5vZ2OYlSeGn2w7y/s+VZMzhGGb9rlUkDtWtwvsE2TWlApFyHggn6qObmQ5DUOu0Mhy6l/ojylyp2Q/C7FMoQWkeBorLKvxf8KFE1lJktCXCxJyptDn8kkNi6Fxszig/flrp5lSWWjDCafyVeyFhvMo22fblzjPOG//wu0+RnOLn9eiWC2CUvJjG11AH+AxWI4UMXY93gq5K1YVLd3EmhI/L1ITAoY3cXoheP0TW9epqe0Zq6lGO+gLiYeWgZJiolSqcHCkTzopbkIZ2cP+yEdeJrYp8ibdO7H0oyXOy48yPElkEobcISzQmTayXQfXyr9YzFPGdM0ZxxKPfpmMox2DTL+mpo1etLOf7ihJNBoR6aAcAWeYLdfqmIlWnVVySW1RPcq31tR4uCP6jpDsbEArXP7lttkWzb0EuBRKN94OVsl7gHuqSSdnrWJwU6jn8EAi9krRQtOKUrz62nOmAkWIe/4fM/3CVjuOgTSUkmuu15SgrbN9aLYp0ct/ nazarewk.id_rsa"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
  ];

  cfg = config.kdn.profile.user.me;
in
{
  options.kdn.profile.user.me = {
    enable = lib.mkEnableOption "enable my user profiles";
  };

  config = lib.mkIf cfg.enable (
    let
      base = {
        description = "Krzysztof Nazarewski";
        isNormalUser = true;
        openssh.authorizedKeys.keys = sshKeys;
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
      };
      nazarewk = base // { uid = 1000; };
      kdn = base // { uid = 31893; };
    in
    {
      kdn.hardware.yubikey.appId = "pam://kdn";

      users.users.kdn = kdn;
      home-manager.users.kdn = { kdn.profile.user.me.nixosConfig = kdn; };

      users.users.nazarewk = nazarewk;
      home-manager.users.nazarewk = { kdn.profile.user.me.nixosConfig = nazarewk; };
    }
  );
}
