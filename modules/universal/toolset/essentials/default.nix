{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.toolset.essentials;
in
{
  options.kdn.toolset.essentials = {
    enable = lib.mkEnableOption "essential CLI tooling";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.toolset.essentials.enable = true; } ];
      })
      {
        kdn.env.packages =
          (with pkgs; [
            curl
            openssh
            screen
            tmux
            wget

            # Working with XDG files
            file
            desktop-file-utils
            xdg-utils
            # xdg-launch # this coredumps under KDE, probably poorly written

            # https://wiki.archlinux.org/title/Default%20applications#Resource_openers
            mimeo

            jq
            git
            openssl

            findutils
            coreutils
            moreutils
            gnugrep
            ripgrep

            zip

            pkgs.kdn.whicher

            # serial consoles usage
            minicom
          ])
          ++ [ ];
        kdn.programs.handlr.enable = lib.mkDefault true;
      }
      (kdnConfig.util.ifHM {
        programs.difftastic.enable = true; # diff highlighter
        programs.difftastic.options.background = "dark"; # diff highlighter
      })
    ]
  );
}
