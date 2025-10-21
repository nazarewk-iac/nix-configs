{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.toolset.essentials;
in
{
  options.kdn.toolset.essentials = {
    enable = lib.mkEnableOption "essential CLI tooling";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
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
        handlr-regex
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
    home-manager.sharedModules = [
      {
        programs.difftastic.enable = true; # diff highlighter
        programs.difftastic.options.background = "dark"; # diff highlighter
      }
    ];
  };
}
