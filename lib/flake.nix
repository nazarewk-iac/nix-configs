{
  inputs.nixpkgs-lib.url = "github:NixOS/nixpkgs/nixos-unstable?dir=lib";

  outputs = { self }: { lib = import ./. { inherit (self.nixpkgs-lib) lib; }; };
}
