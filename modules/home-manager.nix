{ config, lib, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.sharedModules = [{
    home.stateVersion = lib.mkDefault "23.11";
    nixpkgs.config = config.nixpkgs.config;
    xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty { } config.nixpkgs.config;
    home.file.".nixpkgs/config.nix".text = lib.generators.toPretty { } config.nixpkgs.config;
  }];
}
