{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.golang = {
    enable = lib.mkEnableOption "golang development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs;[
      gopls
      delve
    ];
  };
}
