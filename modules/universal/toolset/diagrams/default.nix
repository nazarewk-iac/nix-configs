{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.toolset.diagrams;
in {
  options.kdn.toolset.diagrams = {
    enable = lib.mkEnableOption "diagramming utils";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifNotHMParent {
      kdn.env.packages = with pkgs; [
        mermaid-cli
        drawio
        plantuml
      ];
    })
  ]);
}
