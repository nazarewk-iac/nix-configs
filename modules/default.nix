{ config, lib, pkgs, inputs, self, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.stylix.nixosModules.stylix
    ./nix.nix
    ./home-manager.nix
  ] ++ lib.trivial.pipe ./. [
    lib.filesystem.listFilesRecursive
    # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
  ];

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
  };

  config = lib.mkIf config.kdn.enable {
    disko.enableConfig = lib.mkDefault false;

    nix.registry.nixpkgs.flake = inputs.nixpkgs;
    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixVersions.stable;

    # required to evaluate stylix
    stylix.image = pkgs.fetchurl {
      # non-expiring share link
      url = "https://nc.nazarewk.pw/s/XSR3x6AkwZAiyBo/download/13754-mushrooms-toadstools-glow-photoshop-3840x2160.jpg";
      sha256 = "sha256-1d/kdFn8v0i1PTeOPytYNUB1TxsuBLNf4+nRgSOYQu4=";
    };
  };
}
