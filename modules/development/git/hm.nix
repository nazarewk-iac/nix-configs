{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.development.git;

  inherit (pkgs.kdn) git-utils;
in
{
  options.kdn.development.git = {
    enable = lib.mkEnableOption "Git development utilities";
  };
  config = lib.mkIf cfg.enable {
    programs.git.ignores = [
      ''
        # START kdn.git-utils
        /${git-utils.passthru.worktreesDir}/
        # END kdn.git-utils
      ''
    ];

    home.packages = with pkgs; [
      git
      jujutsu
      git-utils
    ];
  };
}
