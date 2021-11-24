{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
  inputs.wayland.url = "github:nix-community/nixpkgs-wayland";
  inputs.keepass.url = "github:nazarewk/nixpkgs/keepass-keetraytotp";
  inputs.swayr-update.url = "github:polykernel/nixpkgs/swayr-update-patch-1";
  inputs.home-manager.url = "github:nix-community/home-manager";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = inputs:
  let 
    system = "x86_64-linux";
  in
  {
    nixosConfigurations.nazarewk = inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ 
        {
          nix.binaryCachePublicKeys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
          ];
          nix.binaryCaches = [
            "https://cache.nixos.org"
            "https://nixpkgs-wayland.cachix.org"
          ];
          nixpkgs.overlays = [
            inputs.wayland.overlay
            (final: prev: {
              swayr = inputs.swayr-update.legacyPackages.${system}.swayr;
              keepass-keetraytotp = inputs.keepass.legacyPackages.${system}.keepass-keetraytotp;
              keepass-charactercopy = inputs.keepass.legacyPackages.${system}.keepass-charactercopy;
              keepass-qrcodeview = inputs.keepass.legacyPackages.${system}.keepass-qrcodeview;
            })
          ];
        }
        ./legacy/nixos/configuration.nix

        inputs.home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.nazarewk = import ./legacy/hm/home.nix;
        }
      ];
    };
  };
}
