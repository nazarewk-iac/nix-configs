{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.element;
in {
  options.kdn.programs.element = {
    enable = lib.mkEnableOption "element setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      /*
      TODO: try out gomuks https://github.com/tulir/gomuks for better client responsiveness?
      */
      kdn.programs.apps.element-desktop = {
        enable = true;
        package.original = pkgs.element-desktop;
        dirs.cache = [];
        dirs.config = ["Element"];
        dirs.data = [];
        dirs.disposable = [];
        dirs.reproducible = [];
        dirs.state = [];
      };
    }
  ]);
}
