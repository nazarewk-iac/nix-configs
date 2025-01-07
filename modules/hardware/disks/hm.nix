{
  lib,
  pkgs,
  config,
  options,
  utils,
  ...
}: let
  cfg = config.kdn.hardware.disks;
in {
  options.kdn.hardware.disks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
    persist = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {freeformType = (pkgs.formats.json {}).type;});
      default = {};
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      kdn.hardware.disks.persist."usr/cache".directories =
        [
          ".cache/appimage-run" # not sure where exactly it comes from
        ]
        ++ lib.lists.optional config.fonts.fontconfig.enable ".cache/fontconfig";
      kdn.hardware.disks.persist."usr/state".files = [
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
