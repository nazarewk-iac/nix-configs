{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  inherit (kdnConfig) self;
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        xdg.configFile."kdn/source-flake".source = self;

        home.sessionPath = ["$HOME/.local/bin"];
        #systemd.user.tmpfiles.settings.kdn-bin.rules."%h/.local/bin".d = {};
        systemd.user.tmpfiles.rules = [
          "d %h/.local/bin - - - -"
        ];
      }
      {
        xdg.userDirs.enable = pkgs.stdenv.isLinux;
        xdg.userDirs.createDirectories = false;
      }
      {
        kdn.disks.persist."usr/cache".directories =
          [
            ".cache/appimage-run" # not sure where exactly it comes from
          ]
          ++ lib.lists.optional config.fonts.fontconfig.enable ".cache/fontconfig";
        kdn.disks.persist."usr/state".files = [
          ".local/share/fish/fish_history" # A file already exists at ...
          ".ipython/profile_default/history.sqlite"
          ".bash_history"
          ".duckdb_history"
          ".python_history"
          ".usql_history"
          ".zsh_history"
        ];
      }
    ]
  );
}
