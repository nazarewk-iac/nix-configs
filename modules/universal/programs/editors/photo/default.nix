{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.editors.photo;
in
{
  options.kdn.programs.editors.photo.enable = lib.mkEnableOption "Photo editing software";

  config = kdnConfig.util.ifTypes [ "nixos" ] (
    lib.mkIf cfg.enable {
      environment.systemPackages = with pkgs; [
        gimp
        krita
      ];
    }
  );
}
