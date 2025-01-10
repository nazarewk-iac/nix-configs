{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.fs.watch;

  watcherModule = lib.types.submodule ({name, ...} @ args: {
    options.enable = lib.mkOption {
      type = with lib.types; bool;
      default = true;
    };
    options.name = lib.mkOption {
      type = with lib.types; str;
      default = name;
    };
    options.debounce = lib.mkOption {
      type = with lib.types; str;
      default = "1sec";
    };
    options.delay = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    options.initialRun = lib.mkOption {
      type = with lib.types; bool;
      default = false;
    };
    options.extraArgs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };
    options.dirs = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
    };
    options.recursive = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
    };
    options.files = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
    };
    options.exec = lib.mkOption {
      type = with lib.types; listOf str;
      apply = lib.strings.escapeShellArgs;
    };
  });
in {
  options.kdn.fs.watch = {
    enable = lib.mkOption {
      type = with lib.types; bool;
      default = cfg.instances != {};
    };
    instances = lib.mkOption {
      default = {};
      type = with lib.types; attrsOf watcherModule;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.services = lib.pipe cfg.instances [
        (lib.attrsets.filterAttrs (_: fsWatchCfg: fsWatchCfg.enable))
        (lib.attrsets.mapAttrs' (name: fsWatchCfg:
          lib.attrsets.nameValuePair "kdn-fs-watch-${name}" {
            description = "${name} filesystem watcher";
            serviceConfig = {
              RuntimeDirectory = "kdn-fs-watch-${name}";
              WorkingDirectory = "/run/kdn-fs-watch-${name}";
              ExecStart =
                lib.pipe [
                  (lib.getExe pkgs.watchexec)
                  "--on-busy-update=queue"
                  "--debounce=${fsWatchCfg.debounce}"
                  (lib.lists.optional (!fsWatchCfg.initialRun)
                    "--postpone")
                  (lib.lists.optional (fsWatchCfg.delay != null)
                    "--delay-run=${fsWatchCfg.delay}")
                  (builtins.map (dir: "--watch-non-recursive=${dir}") fsWatchCfg.dirs)
                  (lib.pipe (fsWatchCfg.recursive ++ fsWatchCfg.files) [
                    (builtins.concatStringsSep "\n")
                    (text:
                      pkgs.writeTextFile {
                        name = "kdn-fs-watch-${name}-watch-file";
                        inherit text;
                      })
                    (path: "--watch-file=${path}")
                  ])
                  fsWatchCfg.extraArgs
                  fsWatchCfg.exec
                ]
                [
                  lib.lists.flatten
                  lib.escapeShellArgs
                  lib.lists.toList
                ];
            };
            wantedBy = ["default.target"];
          }))
      ];
    }
  ]);
}
