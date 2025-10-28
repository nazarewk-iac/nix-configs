{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) self inputs;

  cfg = config.kdn.profile.hardware.darwin-utm-guest;

  isActive = kdnConfig.features.darwin-utm-guest or false;
  onActive = self.lib.lists.optional isActive;
in {
  imports = [] ++ onActive "${inputs.nixpkgs}/nixos/modules/profiles/qemu-guest.nix";
  options.kdn.profile.hardware.darwin-utm-guest = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = isActive;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        boot.initrd.availableKernelModules = [
          "xhci_pci"
          "sr_mod"
        ];
      }
    ]
  );
}
