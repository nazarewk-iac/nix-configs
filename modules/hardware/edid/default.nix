{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.edid;
  bin = "${pkgs.kdn.linuxhw-edid-fetcher}/bin/linuxhw-edid-fetcher";
  extraFilesKey = "edids";

  pkg = pkgs.runCommand "kdn-hardware-edids" { } (lib.trivial.pipe cfg.displays [
    (lib.mapAttrsToList (name: patterns: ''${bin} ${lib.escapeShellArgs patterns} > "${name}.bin"''))
    (lines: lines ++ [
      "set -x"
      "mkdir -p $out/lib/firmware/edid"
      "mv *.bin $out/lib/firmware/edid/"
      "set +x"
    ])
    lib.flatten
    (builtins.concatStringsSep "\n")
  ]);
in
{
  options.kdn.hardware.edid = {
    enable = lib.mkEnableOption "EDID scripts & utils";

    displays = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {
        "PG278Q_2014" = [ "PG278Q" "2014" ];
        "U2711_2012_1" = [ "U2711" "DELA055" "2560x1440" "2012" ];
        "U2711_2012_2" = [ "U2711" "DELA057" "2560x1440" "2012" ];
      };
    };

    kernelOutputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf (cfg.kernelOutputs != { }) {
      boot.initrd.extraFiles = lib.mapAttrs'
        (output: name: lib.attrsets.nameValuePair
          "${name}.bin"
          { source = "${pkg}/lib/firmware/edid/${name}.bin"; })
        cfg.kernelOutputs;
      boot.kernelParams = lib.trivial.pipe cfg.kernelOutputs [
        (lib.mapAttrsToList (output: name: ''${output}:${name}.bin''))
        (builtins.concatStringsSep ",")
        # see https://wiki.archlinux.org/title/Kernel_mode_setting#Forcing_modes_and_EDID
        (p: [ "drm.edid_firmware=${p}" ])
      ];
    })
    {
      environment.systemPackages = with pkgs; [
        kdn.linuxhw-edid-fetcher
        edid-decode
        read-edid
      ];
    }
  ]);
}
