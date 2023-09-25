{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.git;
in
{
  options.kdn.development.git = {
    enable = lib.mkEnableOption "Git development utilities";
  };
  config = lib.mkIf cfg.enable {
    programs.bash.initExtra = config.programs.zsh.initExtra;
    programs.zsh.initExtra = ''
      gh-cd() {
        cd "$(${pkgs.kdn.git-utils-kdn}/bin/g-dir $1)"
      }
    '';

    home.packages = with pkgs; [
      kdn.git-utils-kdn

      hub
      gh

      git-remote-codecommit
    ];
  };
}
