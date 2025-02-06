{
  config,
  pkgs,
  lib,
  inputs,
  self,
  kdn-features,
  ...
}: let
  cfg = config.kdn.profile.hardware.rpi4;

  onInstaller = self.lib.lists.optional (kdn-features.rpi4 && kdn-features.installer);
  onRpi = self.lib.lists.optional kdn-features.rpi4;
in {
  imports = (
    []
    ++ onRpi inputs.nixos-hardware.nixosModules.raspberry-pi-4
    ++ onRpi "${inputs.nixpkgs}/nixos/modules/profiles/minimal.nix"
    ++ onInstaller "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi-installer.nix"
  );
  options.kdn.profile.hardware.rpi4 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = kdn-features.rpi4;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

      fileSystems = lib.mkIf (!kdn-features.installer) {
        "/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "ext4";
        };
      };
    }
  ]);
}
