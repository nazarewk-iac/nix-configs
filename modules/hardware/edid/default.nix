{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.edid;

  generator = edid-generator.overrideAttrs { };
in
{
  options.nazarewk.hardware.edid = {
    enable = mkEnableOption "EDID scripts & utils";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      (kdn.edid-generator.override {
        modelines = [
          ''Modeline "PG278Q_2560x1440"       241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync''
          ''Modeline "PG278Q_2560x1440_120"   497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync''
          ''Modeline "U2711_2560x1440"        241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync''
        ];
      })
      edid-decode
      read-edid
    ];
  };
}
