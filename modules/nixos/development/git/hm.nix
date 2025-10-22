{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.git;

  inherit (pkgs.kdn) git-utils;
in {
  options.kdn.development.git = {
    enable = lib.mkEnableOption "Git development utilities";
  };
  config = lib.mkIf cfg.enable {
    programs.git.enable = true;

    programs.git.ignores = [
      ''
        # START kdn.git-utils
        /${git-utils.passthru.worktreesDir}/
        # END kdn.git-utils
      ''
    ];
    programs.difftastic.git.enable = true;

    home.packages = with pkgs; [
      git
      jujutsu
      git-utils
      gh
    ];
  };
}
