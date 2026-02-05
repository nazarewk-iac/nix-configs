{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.programs.torrent;
in {
  options.kdn.programs.torrent = {
    enable = lib.mkEnableOption "Torrent client setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.programs.torrent = lib.mkDefault cfg;}];})
    (kdnConfig.util.ifNotHMParent {
      kdn.apps.deluge = {
        enable = true;
        dirs.cache = [];
        dirs.config = ["deluge"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
        files.cache = [];
      };
    })
  ]);
}
