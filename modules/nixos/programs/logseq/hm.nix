{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.logseq;
in
{
  options.kdn.programs.logseq = {
    enable = lib.mkEnableOption "logseq setup";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        kdn.programs.apps.logseq = {
          enable = true;
          dirs.cache = [ ];
          dirs.config = [ "Logseq" ];
          dirs.data = [ ];
          dirs.disposable = [ ];
          dirs.reproducible = [ ];
          dirs.state = [ ];
        };
      }
    ]
  );
}
