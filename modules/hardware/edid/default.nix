{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.hardware.edid;

  edids = (pkgs.kdn.linuxhw-edid-fetcher.override {
    displays = cfg.displays;
  });

  initrdPaths = lib.mapAttrs (name: v: "edids/lib/firmware/edid/${name}.bin") cfg.displays;
in
{
  options.kdn.hardware.edid = {
    enable = mkEnableOption "EDID scripts & utils";

    displays = mkOption {
      type = types.attrsOf (types.listOf types.string);
      default = {
        "PG278Q_2014" = [ "PG278Q" "2014" ];
        "U2711_2012_1" = [ "U2711" "2560x1440" "2012" "DELA055" ];
        "U2711_2012_2" = [ "U2711" "2560x1440" "2012" "DELA057" ];
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
        edids
        edid-decode
        read-edid
      ];
    }
  ]);
}
