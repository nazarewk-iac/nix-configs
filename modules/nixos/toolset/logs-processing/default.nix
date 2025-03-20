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
    environment.systemPackages =
      (with pkgs; [
        # https://github.com/trungdq88/logmine
        # https://github.com/ynqa/logu
        # https://github.com/logpai/logparser
        angle-grinder # https://github.com/rcoh/angle-grinder
        lnav # https://lnav.org/
      ])
      ++ [];
  };
}
