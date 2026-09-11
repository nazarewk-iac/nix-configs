{

  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.edid;
in
{
  options.kdn.hw.edid = {
    enable = lib.mkEnableOption "EDID scripts & utils";

    modelines = lib.mkOption {
      type = with lib.types; attrsOf str;
      description = ''
        XFree86 modelines, by name. Each name becomes an `edid/<name>.bin` file in initrd,
        and `hardware.display.outputs.<output>.edid` names that file.
        A name must hold 12 characters or fewer.

        `attrsOf` supplies an empty set, so a host with no monitor data adds no modeline.
        The nixpkgs `apply` then returns `null`, which is the same state as today's
        `kdn.hw.edid.enable = false`.
      '';
      example = lib.literalExpression ''
        {
          "MON_60" = "    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifTypes [ "nixos" ] {
        kdn.env.packages = with pkgs; [
          linuxhw-edid-fetcher
          edid-decode
          read-edid
          edido
        ];

        hardware.display.edid.modelines = cfg.modelines;
      })
    ]
  );
}
