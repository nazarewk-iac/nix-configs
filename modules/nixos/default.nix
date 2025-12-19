{
  config,
  lib,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) inputs;
in {
  imports =
    [
      ../shared/darwin-nixos
      ./ascii-workaround.nix
      inputs.disko.nixosModules.disko
      inputs.home-manager.nixosModules.home-manager
      inputs.lanzaboote.nixosModules.lanzaboote
      inputs.nur.modules.nixos.default
      inputs.preservation.nixosModules.preservation
      inputs.sops-nix.nixosModules.sops
      inputs.angrr.nixosModules.angrr
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      withDefault = true;
    };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {
        # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
        disko.enableConfig = lib.mkDefault false;
      }
      {
        home-manager.sharedModules = [
          {imports = [../home-manager];}
          ({kdnConfig, ...}: {
            imports = kdnConfig.util.loadModules {
              curFile = ./default.nix;
              src = ./.;
            };
          })
        ];
      }
    ]
  );
}
