{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.programs.editors.photo;
in {
  options.kdn.programs.editors.photo.enable = lib.mkEnableOption "Photo editing software";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gimp
      krita
    ];
  };
}
