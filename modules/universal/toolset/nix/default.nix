{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.toolset.nix;
in {
  options.kdn.toolset.nix = {
    enable = lib.mkEnableOption "nix management utilities setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [{kdn.toolset.nix.enable = true;}];
    })
    (kdnConfig.util.ifNotHMParent {
      kdn.env.packages = with pkgs; [
        nix-derivation # pretty-derivation
        nix-weather # check for packages in cache
        nix-output-monitor
        nix-du
        nix-tree
        nix-update
        pkgs.kdn.kdn-nix
      ];
    })
  ]);
}
