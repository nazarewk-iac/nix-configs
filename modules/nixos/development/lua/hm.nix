{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.nodejs;
in {
  options.kdn.development.lua = {
    enable = lib.mkEnableOption "lua development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs; [
      lua-language-server
    ];
  };
}
