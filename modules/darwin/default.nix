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
      ../universal
      inputs.home-manager.darwinModules.default
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.sops-nix.darwinModules.default
      inputs.angrr.nixosModules.angrr
    ]
    ++ kdnConfig.util.loadModules {
      curFile = ./default.nix;
      src = ./.;
      withDefault = true;
    };

  config = lib.mkIf config.kdn.enable (
    lib.mkMerge [
      {kdn.desktop.enable = lib.mkDefault true;}
      {networking.localHostName = config.kdn.hostName;}
      {
        homebrew.enable = true;
        homebrew.onActivation.upgrade = false;

        nix-homebrew.enable = true;
        nix-homebrew.enableRosetta = true;
        nix-homebrew.mutableTaps = false;

        nix-homebrew.taps = let
          prefix = "brew-tap--";
        in
          lib.pipe inputs [
            (lib.attrsets.filterAttrs (name: _: lib.strings.hasPrefix prefix name))
            (lib.attrsets.mapAttrs' (
              name: src: {
                name = lib.pipe name [
                  (lib.strings.removePrefix prefix)
                  (builtins.replaceStrings ["--"] ["/"])
                ];
                value = src;
              }
            ))
          ];
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
      {
        networking.computerName = lib.mkDefault config.kdn.hostName;
      }
    ]
  );
}
