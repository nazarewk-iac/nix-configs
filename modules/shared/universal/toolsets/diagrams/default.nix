{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.toolset.diagrams;
in {
  options.kdn.toolset.diagrams = {
    enable = lib.mkEnableOption "diagramming utils";
  };

  config = lib.mkIf cfg.enable {
    kdn.packages = with pkgs; [
      mermaid-cli
    ];
  };
}
