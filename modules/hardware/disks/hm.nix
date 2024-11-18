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
  };

  config = lib.mkMerge [
    (lib.mkIf (!cfg.enable) {home.persistence = lib.mkForce {};})
    # the rest of configs are in ./handle-options.nix
    (lib.mkIf cfg.enable {
      impermanence.defaultDirectoryMethod = lib.mkDefault "external";
      impermanence.defaultFileMethod = lib.mkDefault "external";
      home.persistence."usr/data".directories = [
        "Videos"
        "Documents"
      ];
      home.persistence."usr/cache".directories =
        [
          "Downloads"
          ".cache/appimage-run" # not sure where exactly it comes from
        ]
        ++ lib.lists.optional config.fonts.fontconfig.enable ".cache/fontconfig";
      home.persistence."usr/state".files = [
        #".local/share/fish/fish_history" # A file already exists at ...
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
