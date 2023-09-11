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
    ./nix.nix
    ./home-manager.nix
  ] ++ nixosModules;

  options.kdn = {
    enable = lib.mkEnableOption "basic Nix configs for kdn";
  };

  config = lib.mkIf config.kdn.enable {
    disko.enableConfig = lib.mkDefault false;

    nix.settings.auto-optimise-store = true;
    nix.package = pkgs.nixVersions.stable;

    home-manager.extraSpecialArgs = { nixosConfig = config; };
    home-manager.sharedModules = hmModules ++ [{
      home.enableNixpkgsReleaseCheck = true;
      xdg.enable = true;
    }];
  };
}
