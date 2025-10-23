{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.fs;
in {
  options.kdn.toolset.fs = {
    enable = lib.mkEnableOption "linux utils";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{kdn.toolset.fs.enable = true;}];

    kdn.toolset.tracing.enable = lib.mkDefault true;
    kdn.toolset.fs.encryption.enable = lib.mkDefault true;
  };
}
