{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.logs-processing;
in {
  options.kdn.toolset.logs-processing = {
    enable = lib.mkEnableOption "logs processing tooling";
  };

  config = lib.mkIf cfg.enable {
    kdn.programs.apps.lnav = {
      # https://lnav.org/
      enable = true;
      package.original = pkgs.lnav;
      dirs.cache = [];
      dirs.config = ["lnav"];
      dirs.data = [];
      dirs.disposable = [];
      dirs.reproducible = [];
      dirs.state = [];
    };
  };
}
