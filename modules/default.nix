{ config, lib, pkgs, inputs, self, ... }:
let
  nixosModules = lib.trivial.pipe ./. [
    lib.filesystem.listFilesRecursive
    # lib.substring expands paths to nix-store paths: "/nix/store/6gv1rzszm9ly6924ndgzmmcpv4jz30qp-default.nix"
    (lib.filter (path: (lib.hasSuffix "/default.nix" (toString path)) && path != ./default.nix))
  ];
  hmModules = lib.trivial.pipe ./. [
    lib.filesystem.listFilesRecursive
    (lib.filter (path: (lib.hasSuffix "/hm.nix" (toString path))))
  ];
in
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
  ] ++ nixosModules;

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
  };

  config = lib.mkIf config.kdn.enable {
    disko.enableConfig = lib.mkDefault false;

    nixpkgs.config.permittedInsecurePackages = [
      "qtwebkit-5.212.0-alpha4"

      # see https://github.com/NixOS/nixpkgs/blob/1c4d9e9a752232eb35579ab9d213ab217897cb6f/pkgs/top-level/release.nix#LL22C1-L30C7
      "openssl-1.1.1t"
      "nodejs-16.20.1" # required by kibana

      # TODO: remove after poetry2nix gets updated, see:
      # see 2.29 pinned at nixos-unstable https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/tools/poetry2nix/poetry2nix/pkgs/poetry/poetry.lock#L1505
      "python3.11-requests-2.29.0"
      "python3.11-cryptography-40.0.2"
    ];

    nix.settings.trusted-public-keys = [
      "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixpkgs-update.cachix.org-1:6y6Z2JdoL3APdu6/+Iy8eZX2ajf09e4EE9SnxSML1W8="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "krul.kdn.im:9D33FhBuxCj/20Ct2ASHx3SqJ5FmfT8+BgoSzTwAZMc="
    ];
    nix.settings.substituters = [
      "https://nixpkgs-wayland.cachix.org"
      "https://nix-community.cachix.org"
      "https://nixpkgs-update.cachix.org"
      "https://devenv.cachix.org"
    ];
    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixVersions.stable;
    nix.extraOptions = ''
      experimental-features = nix-command flakes
    '';
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.allowAliases = true;

    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.extraSpecialArgs = { nixosConfig = config; };
    home-manager.sharedModules = hmModules ++ [
      (
        let
          cfg = ''
            { allowUnfree = true; allowAliases = true; }
          '';
        in
        {
          home.enableNixpkgsReleaseCheck = true;
          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.allowAliases = true;
          xdg.configFile."nixpkgs/config.nix".text = cfg;
          home.file.".nixpkgs/config.nix".text = cfg;
          xdg.enable = true;
        }
      )
    ];
  };
}
