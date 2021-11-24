{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
  inputs.nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
  inputs.nixpkgs-keepass.url = "github:nazarewk/nixpkgs/keepass-keetraytotp";
  inputs.nixpkgs-swayr-update.url = "github:polykernel/nixpkgs/swayr-update-patch-1";

  outputs = { self, nixpkgs, nixpkgs-wayland, nixpkgs-keepass, nixpkgs-swayr-update }: 
  let 
    system = "x86_64-linux";
    pkgs-keepass = nixpkgs-keepass.legacyPackages.${system};
    pkgs-swayr-update = nixpkgs-swayr-update.legacyPackages.${system};
  in
  {
    nixosConfigurations.nazarewk = nixpkgs.lib.nixosSystem {
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
            nixpkgs-wayland.overlay
            (final: prev: {
              swayr = pkgs-swayr-update.swayr;
              keepass-keetraytotp = pkgs-keepass.keepass-keetraytotp;
              keepass-charactercopy = pkgs-keepass.keepass-charactercopy;
              keepass-qrcodeview = pkgs-keepass.keepass-qrcodeview;
            })
          ];
        }
        ./legacy/nixos/configuration.nix
      ];
    };
  };
}
