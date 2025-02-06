{
  config,
  pkgs,
  lib,
  inputs,
  isRPi4 ? false,
  isRPi4Installer ? false,
  ...
}: let
  cfg = config.kdn.profile.hardware.rpi4;

  onInstaller = lib.lists.optional isRPi4Installer;
in {
  imports = lib.lists.optionals isRPi4 (
    [
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      "${inputs.nixpkgs}/nixos/modules/profiles/minimal.nix"
    ]
    ++ onInstaller "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi-installer.nix"
  );
  options.kdn.profile.hardware.rpi4 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = isRPi4;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

      fileSystems = lib.mkIf (!isRPi4Installer) {
        "/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "ext4";
        };
      };
    }
  ]);
}
