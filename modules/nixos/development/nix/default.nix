{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nix;
in {
  options.kdn.development.nix = {
    enable = lib.mkEnableOption "nix development/debugging";
  };

  config = lib.mkIf cfg.enable {
    kdn.programs.nix-utils.enable = true;
    home-manager.sharedModules = [{kdn.development.nix.enable = true;}];
  };
}
