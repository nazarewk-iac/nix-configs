{

  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.programs.editors.photo;
in
{
  options.kdn.programs.editors.photo.enable = lib.mkEnableOption "Photo editing software";

  config = lib.mkIf cfg.enable {
    kdn.env.packages = with pkgs; [
      gimp
      krita
    ];
  };
}
