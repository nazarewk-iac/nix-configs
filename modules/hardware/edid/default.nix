{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.edid;

  generated = pkgs.kdn.edid-generator.overrideAttrs {
    clean = true;
    modelines = cfg.modelines;
  };
in
{
  options.kdn.hardware.edid = {
    enable = lib.mkEnableOption "EDID scripts & utils";

    modelines = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # WARNING: must be 12 characters or less! see
        "PG278Q_60" = ''    241.50   2560 2608 2640 2720   1440 1443 1448 1481   -hsync +vsync'';
        "PG278Q_120" = ''   497.75   2560 2608 2640 2720   1440 1443 1448 1525   +hsync -vsync'';
        "U2711_60" = ''     241.50   2560 2600 2632 2720   1440 1443 1448 1481   -hsync +vsync'';
      };
      apply = modelines: lib.trivial.pipe modelines [
        (lib.mapAttrsToList (name: value: ''Modeline "${name}" ${value}''))
        (builtins.map (line: "${line}\n"))
        (lib.strings.concatStringsSep "")
      ];
    };

    kernelOutputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    # putting package containing `lib/firmware/edid/XXX.bin` should enable using `edid/XXX.bin` in kernel params
    # see https://docs.kernel.org/admin-guide/kernel-parameters.html?highlight=edid_firmware
    hardware.firmware = [ generated ];

    boot.kernelParams = lib.trivial.pipe cfg.kernelOutputs [
      (lib.mapAttrsToList (output: name: ''${output}:edid/${name}.bin''))
      (builtins.concatStringsSep ",")
      # see https://wiki.archlinux.org/title/Kernel_mode_setting#Forcing_modes_and_EDID
      (p: [ "drm.edid_firmware=${p}" ])
    ];
    environment.systemPackages = with pkgs; [
      kdn.linuxhw-edid-fetcher
      edid-decode
      read-edid
    ];
  };
}
