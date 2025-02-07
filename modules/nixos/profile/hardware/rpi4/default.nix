{
  config,
  pkgs,
  lib,
  kdn,
  ...
}: let
  inherit (kdn) self inputs;

  cfg = config.kdn.profile.hardware.rpi4;

  rpi4.any = kdn.features.rpi4;
  rpi4.normal = rpi4.any && !kdn.features.installer;
  rpi4.installer = rpi4.any && kdn.features.installer;
in {
  imports = self.lib.lists.optionals rpi4.any (
    [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ]
    ++ self.lib.lists.optional rpi4.installer "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
  );
  options.kdn.profile.hardware.rpi4 = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = kdn.features.rpi4;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      boot.kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;

      boot.loader.systemd-boot.enable = lib.mkForce false;

      fileSystems = lib.mkIf rpi4.normal {
        "/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "ext4";
        };
      };
    }
  ]);
}
