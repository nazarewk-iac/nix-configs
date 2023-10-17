{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.edid;

  generated = pkgs.kdn.edid-generator.overrideAttrs {
    clean = true;
    modelines = lib.trivial.pipe cfg.modelines [
      (lib.mapAttrsToList (name: value: ''Modeline "${name}" ${value}''))
      (builtins.map (line: "${line}\n"))
      (lib.strings.concatStringsSep "")
    ];
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
    /* results in:
        initrd-linux> /init -> /nix/store/1zmmnm0r0bdga398rl7fc7s4hkyqxjk4-systemd-254.3/lib/systemd/systemd
        initrd-linux> /lib/firmware -> /nix/store/xkrkbaicdyy2rn3vamk3lq336l8rh3v9-linux-6.1.54-rt15-modules-shrunk/lib/firmware
        initrd-linux> /lib/firmware/edid/PG278Q_120.bin -> /nix/store/hsfipmg5lfiv4ia0l7ya9hmk5dr1c6qw-edid-generator-master-2023-10-17/lib/firmware/edid/PG278Q_120.bin
        initrd-linux> Error: failed to create directories to "./root//lib/firmware/edid"
        initrd-linux> Caused by:
        initrd-linux>     Permission denied (os error 13)
        initrd-linux> Location:
        initrd-linux>     src/main.rs:258:18
    */
    # TODO: remove this "fix" at some point?
    #   see https://github.com/NixOS/nixpkgs/blob/5e4c2ada4fcd54b99d56d7bd62f384511a7e2593/nixos/modules/system/boot/systemd/initrd.nix#L383-L385

    boot.initrd.systemd.contents."/lib/firmware".source =
      let
        # "/lib/modules".source = "${modulesClosure}/lib/modules";
        modulesClosure = lib.strings.removeSuffix "/lib/modules" config.boot.initrd.systemd.contents."/lib/modules".source;

        joined = pkgs.symlinkJoin {
          name = "kdn-initrd-firmware";
          paths = [ modulesClosure generated ];
        };
      in
      lib.mkForce "${joined}/lib/firmware";

    /*
      boot.initrd.systemd.contents = lib.mapAttrs'
      (name: _: lib.attrsets.nameValuePair
        "/lib/firmware/edid/${name}.bin"
        { source = "${generated}/lib/firmware/edid/${name}.bin"; })
      cfg.modelines;
    */
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
