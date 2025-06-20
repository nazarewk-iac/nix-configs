{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.development.llm.online;
in {
  options.kdn.development.llm.online = {
    enable = lib.mkEnableOption "tools for working with online LLMs";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{kdn.development.llm.online.enable = true;}];
    environment.systemPackages = with pkgs; [
    ];
  };
}
