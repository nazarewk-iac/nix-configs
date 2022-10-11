{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.edid;

  edids = (pkgs.kdn.edid-generator.override {
    clean = true;
    modelines = lib.mapAttrsToList (name: line: ''Modeline "${name}" ${line}'') cfg.modelines;
  });

  initrdPaths = lib.mapAttrs (name: v: "edids/lib/firmware/edid/${name}.bin") cfg.modelines;
in
{
  options.nazarewk.hardware.edid = {
    enable = mkEnableOption "EDID scripts & utils";

    modelines = mkOption {
      type = types.attrsOf types.string;
      default = {
        "PG278Q_2560x1440" = ''     241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync'';
        "PG278Q_2560x1440@120" = '' 497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync'';
        "U2711_2560x1440" = ''      241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync'';
      };
    };

    kernelOutputs = mkOption {
      type = types.attrsOf types.string;
      default = { };
    };

    package = mkOption {
      type = types.package;
      default = edids;
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.kernelOutputs != { }) {
      boot.initrd.extraFiles."edids".source = edids;
      boot.kernelParams = lib.flatten (lib.mapAttrsToList
        # [    1.987896] platform DVI-D-1: Direct firmware load for edids/lib/firmware/edid/U2711_2560x1440.bin failed with error -2
        # [    1.987902] [drm:edid_load [drm]] *ERROR* Requesting EDID firmware "edids/lib/firmware/edid/U2711_2560x1440.bin" failed (err=-2)
        (output: name: [
          ''drm.edid_firmware=${output}:${initrdPaths."${name}"}''
          # see https://www.reddit.com/r/archlinux/comments/oujnxs/new_amdgpu_unable_to_set_edid_on_one_monitor/
          "video=${output}:e"
        ])
        cfg.kernelOutputs);
    })
    {
      environment.systemPackages = with pkgs; [
        edid-decode
        read-edid
      ];
    }
  ]);
}
