{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.disks;
in {
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.hw.disks.persist."usr/cache".directories =
        [
          ".cache/appimage-run" # not sure where exactly it comes from
        ]
        ++ lib.lists.optional config.fonts.fontconfig.enable ".cache/fontconfig";
      kdn.hw.disks.persist."usr/state".files = [
        ".local/share/fish/fish_history" # A file already exists at ...
        ".ipython/profile_default/history.sqlite"
        ".bash_history"
        ".duckdb_history"
        ".python_history"
        ".usql_history"
        ".zsh_history"
      ];
    })
  ];
}
