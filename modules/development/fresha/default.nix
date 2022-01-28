{ config, ... }: {
  config.home-manager.sharedModules = [./hm.nix];
}