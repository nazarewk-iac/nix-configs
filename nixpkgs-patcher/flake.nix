{
  inputs.nixpkgs-upstream.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.nixpkgs.url = "github:nazarewk/nixpkgs/nixos-unstable";
  inputs.nixpkgs-patch-2.url = "https://github.com/nazarewk/nixpkgs/compare/nixos-unstable..netbird-improvements.patch";
  inputs.nixpkgs-patch-2.flake = false;
  inputs.nixpkgs-patch-3.url = "https://github.com/nazarewk/nixpkgs/compare/nixos-unstable..add/idea-ultimate-eap.patch";
  inputs.nixpkgs-patch-3.flake = false;

  outputs = _: { };
}
