{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.web = {
    enable = lib.mkEnableOption "web development";
  };

  config = lib.mkIf cfg.enable {
    kdn.development.nodejs.enable = true;
    programs.helix.extraPackages = with pkgs; [
      nodePackages.vscode-css-languageserver-bin
      nodePackages.vscode-html-languageserver-bin
    ];
  };
}
