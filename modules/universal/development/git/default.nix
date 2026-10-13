{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.development.git;

  inherit (pkgs.kdn) git-utils;
in
{
  options.kdn.development.git = {
    enable = lib.mkEnableOption "Git development utilities";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.development.git = lib.mkDefault cfg; } ];
    })
    (kdnConfig.util.ifHM (
      lib.mkIf cfg.enable {
        programs.git.enable = true;

        programs.git.ignores = [
          ''
            # START kdn.git-utils
            /${git-utils.passthru.worktreesDir}/
            # END kdn.git-utils
          ''
        ];

        kdn.env.packages = with pkgs; [
          git
          git-utils
          gh

          jjui
        ];
        programs.jujutsu.enable = true;
        programs.jujutsu.settings = {
          ui.default-command = "log";
          ui.paginate = "auto"; # turn off pager by default
        }
        // lib.optionalAttrs (!config.kdn.minimalServer) {
          # `difftastic` is a large Rust binary. A minimal server keeps the plain jj diff.
          ui.diff-formatter = [
            (lib.getExe config.programs.difftastic.package)
            "--color=always"
            "$left"
            "$right"
          ];
        };
        programs.difftastic.git.enable = lib.mkIf (!config.kdn.minimalServer) true;
      }
    ))
  ];
}
