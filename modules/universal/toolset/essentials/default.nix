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
            (lib.hiPrio coreutils) # for higher priority than kill from util-linux
            moreutils
            gnugrep
            ripgrep

            zip
            unzip

            pkgs.kdn.whicher

            # serial consoles usage
            minicom
          ])
          ++ [ ];
        kdn.programs.handlr.enable = lib.mkDefault true;
      }
      (kdnConfig.util.ifHM {
        # A `lib.mkDefault` on each, so a consumer drops difftastic or picks a light background.
        programs.difftastic.enable = lib.mkDefault true; # diff highlighter
        programs.difftastic.options.background = lib.mkDefault "dark"; # diff highlighter
      })
    ]
  );
}
