{ lib, config, ... }:
with lib;
let
  sshKeys = [
    "ssh-rsa ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAYEAvM4y0G5vZ2OYlSeGn2w7y/s+VZMzhGGb9rlUkDtWtwvsE2TWlApFyHggn6qObmQ5DUOu0Mhy6l/ojylyp2Q/C7FMoQWkeBorLKvxf8KFE1lJktCXCxJyptDn8kkNi6Fxszig/flrp5lSWWjDCafyVeyFhvMo22fblzjPOG//wu0+RnOLn9eiWC2CUvJjG11AH+AxWI4UMXY93gq5K1YVLd3EmhI/L1ITAoY3cXoheP0TW9epqe0Zq6lGO+gLiYeWgZJiolSqcHCkTzopbkIZ2cP+yEdeJrYp8ibdO7H0oyXOy48yPElkEobcISzQmTayXQfXyr9YzFPGdM0ZxxKPfpmMox2DTL+mpo1etLOf7ihJNBoR6aAcAWeYLdfqmIlWnVVySW1RPcq31tR4uCP6jpDsbEArXP7lttkWzb0EuBRKN94OVsl7gHuqSSdnrWJwU6jn8EAi9krRQtOKUrz62nOmAkWIe/4fM/3CVjuOgTSUkmuu15SgrbN9aLYp0ct/ nazarewk.id_rsa"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
  ];
in
mkMerge [
  {
    nazarewk.hardware.yubikey.enable = true;
    nazarewk.programs.gnupg.enable = true;

    users.users.nazarewk.description = "Krzysztof Nazarewski";
    users.users.nazarewk.uid = 1000;
    users.users.nazarewk.isNormalUser = true;
    users.users.nazarewk.extraGroups = [
      "kvm"
      "libvirtd"
      "networkmanager"
      "power"
      "wheel"
      "mlocate"
    ];

    users.users.nazarewk.openssh.authorizedKeys.keys = sshKeys;

    home-manager.users.nazarewk = import ./home.nix;
  }
  (mkIf config.nazarewk.docker.enable {
    users.users.nazarewk.extraGroups = [
      "docker"
    ];
  })
  (mkIf config.programs.adb.enable {
    users.users.nazarewk.extraGroups = [
      "adbusers"
    ];
  })
  (mkIf config.services.printing.enable {
    users.users.nazarewk.extraGroups = [
      "scanner"
      "lp"
    ];
  })
  (mkIf config.nazarewk.hardware.modem.enable {
    users.users.nazarewk.extraGroups = [
      "dialout"
    ];
  })
  (lib.mkIf config.nazarewk.headless.enableGUI {
    users.users.nazarewk.extraGroups = [
      "audio"
      "pipewire"
      "video"
    ];
  })
]
