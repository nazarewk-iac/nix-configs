{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}:
kdnConfig.util.ifTypes ["nixos"] (
  let
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
              (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.profile.hardware.darwin-utm-guest = lib.mkDefault cfg;}];})
{
          boot.initrd.availableKernelModules = [
            "xhci_pci"
            "sr_mod"
          ];
        }
      ]
    );
  }
)
