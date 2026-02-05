{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.programs.logseq;
in {
  options.kdn.programs.logseq = {
    enable = lib.mkEnableOption "logseq setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.logseq = lib.mkDefault cfg;}];})
    (kdnConfig.util.ifNotHMParent {
      kdn.apps.logseq = {
        enable = true;
        dirs.cache = [];
        dirs.config = [
          /*
          ~/.config/Logseq contains everything, some of those are:
            - a whole Electron data, cache & logs directories
            - some preferences files
          */
          "Logseq"
          /*
          ~/.logseq contains some pieces of persistent configuration:
            - Logseq forgot opened graphs if it wasn't persisted
          */
          "/.logseq"
        ];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    })
  ]);
}
