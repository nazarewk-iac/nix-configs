{ lib, ... }: {
  nixosSystem = self:
    { modules ? [ ]
    , system ? "x86_64-linux"
    , ...
    }: lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit system;
        inherit (self) inputs lib;
        waylandPkgs = self.inputs.nixpkgs-wayland.packages.${system};
      };

      modules = [
        self.nixosModules.default
        { nixpkgs.overlays = [ self.overlays.default ]; }
      ] ++ modules;
    };
}
