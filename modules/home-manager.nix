{ config, lib, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.sharedModules = [{
    nixpkgs.config = config.nixpkgs.config;
    xdg.configFile."nixpkgs/config.nix".text = lib.generators.toPretty { } config.nixpkgs.config;
    home.file.".nixpkgs/config.nix".text = lib.generators.toPretty { } config.nixpkgs.config;
  }];
}
