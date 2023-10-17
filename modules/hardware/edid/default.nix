{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.edid;

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
      hardware.firmware =
        # putting package containing `lib/firmware/edid/XXX.bin` should enable using `edid/XXX.bin` in kernel params
        # see https://docs.kernel.org/admin-guide/kernel-parameters.html?highlight=edid_firmware
        let
          fetch = "${pkgs.kdn.linuxhw-edid-fetcher}/bin/linuxhw-edid-fetcher";
          pkg =
            pkgs.runCommand "kdn-hardware-edids" { } (lib.trivial.pipe cfg.displays [
              (lib.mapAttrsToList (name: patterns: ''${fetch} ${lib.escapeShellArgs patterns} > "$out/lib/firmware/edid/${name}.bin"''))
              (l: [ "mkdir -p $out/lib/firmware/edid" ] ++ l)
              (builtins.concatStringsSep "\n")
            ]);
        in
        [ pkg ];
      boot.kernelParams = lib.trivial.pipe cfg.kernelOutputs [
        (lib.mapAttrsToList (output: name: ''${output}:edid/${name}.bin''))
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
