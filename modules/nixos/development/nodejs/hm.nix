{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nodejs;
in {
  options.kdn.development.nodejs = {
    enable = lib.mkEnableOption "Node JS development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      nodePackages.typescript-language-server
    ];
  };
}
