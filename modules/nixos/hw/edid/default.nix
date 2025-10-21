{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.kdn.hw.edid;
in
{
  options.kdn.hw.edid = {
    enable = lib.mkEnableOption "EDID scripts & utils";
  };

  config = lib.mkIf cfg.enable {
    hardware.display.edid.modelines = {
      "PG278Q_60" = "    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync";
      "PG278Q_120" = "   497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync";
      "U2711_60" = "     241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync";
    };

    environment.systemPackages = with pkgs; [
      linuxhw-edid-fetcher
      edid-decode
      read-edid
      edido
    ];
  };
}
