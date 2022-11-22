{ config, lib, pkgs, inputs, self, ... }:
let
  nixosModules = lib.pipe ./. [
    lib.filesystem.listFilesRecursive
    # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
  ];
  hmModules = lib.pipe ./. [
    lib.filesystem.listFilesRecursive
    (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path))))
  ];
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ] ++ nixosModules;

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
  };

  config = lib.mkIf config.kdn.enable {
    nixpkgs.config.permittedInsecurePackages = [
      "qtwebkit-5.212.0-alpha4"
    ];

    nix.settings.trusted-public-keys = [
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
    ];
    nix.settings.substituters = [
      "https://nixpkgs-wayland.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-update.cachix.org"
    ];
    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixVersions.stable;
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowAliases = false;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "backup";
    home-manager.extraSpecialArgs = { nixosConfig = config; };
    home-manager.sharedModules = hmModules ++ [
      (
        let
          cfg = ''
            { allowUnfree = true; allowAliases = false; }
          '';
        in
        {
          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.allowAliases = false;
          xdg.configFile."nixpkgs/config.nix".text = cfg;
          home.file.".nixpkgs/config.nix".text = cfg;
        }
      )
    ];
  };
}
