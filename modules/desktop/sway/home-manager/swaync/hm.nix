{ config, pkgs, lib, ... }:
let
  cfg = config.services.swaync;
in
{
  options.services.swaync = {
    enable = lib.mkEnableOption "swaynotificationcenter daemon";

    package = lib.mkOption {
      type = with lib.types; package;
      default = pkgs.swaynotificationcenter;
      defaultText = lib.literalExpression "pkgs.swaynotificationcenter";
      description = "Package providing {command} `swaync`.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    xdg.dataFile."dbus-1/services/org.erikreider.swaync.service".source =
      "${pkgs.dunst}/share/dbus-1/services/org.erikreider.swaync.service";
  };
}
