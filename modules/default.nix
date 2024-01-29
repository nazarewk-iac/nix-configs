{ config, lib, pkgs, inputs, ... }: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    ./nix.nix
    ./home-manager.nix
    ./stylix.nix
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
    nix.package = pkgs.nixVersions.stable;
  };
}
