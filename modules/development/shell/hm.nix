{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.terraform;
in
{
  options.kdn.development.shell = {
    enable = lib.mkEnableOption "shell development";
  };

  config = lib.mkIf cfg.enable {
    programs.helix.extraPackages = with pkgs;[
      nodePackages.bash-language-server
      shellcheck
      shfmt

      cmake-language-server
    ];
  };
}
