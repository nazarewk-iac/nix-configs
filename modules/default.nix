{ config, lib, pkgs, inputs, self, ... }: {
  imports = [
    ./ascii-workaround.nix
    ./home-manager.nix
    ./nix.nix
    ./stylix.nix
    inputs.disko.nixosModules.disko
    inputs.home-manager.nixosModules.home-manager
    inputs.impermanence.nixosModules.impermanence
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.lanzaboote.nixosModules.uki
    inputs.nur.nixosModules.nur
    inputs.sops-nix.nixosModules.sops
  ] ++ lib.trivial.pipe ./. [
    lib.filesystem.listFilesRecursive
    # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
  ];

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
  };

  config = lib.mkIf config.kdn.enable {
    # lib.mkDefault is 1000, lib.mkOptionDefault is 1500
    disko.enableConfig = lib.mkDefault false;

    nix.registry.nixpkgs.flake = inputs.nixpkgs;
    nix.settings.auto-optimise-store = true;
    # 2024-04-04: .stable is quite old at 2.18
    nix.package = pkgs.nixVersions.latest;
    nixpkgs.overlays = [ self.overlays.default ];
  };
}
