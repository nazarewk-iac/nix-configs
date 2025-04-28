{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.basic;
in {
  options.kdn.hw.basic = {
    enable = lib.mkEnableOption "hardware discovery scripts";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs;
      [
        dmidecode
        glxinfo
      ]
      ++ lib.lists.optionals (with pkgs.stdenv; isLinux && isx86_64) [
        hardinfo2 # 2025-04-28: error: 'hardinfo' has been removed as it was abandoned upstream. Consider using 'hardinfo2' instead.
      ]
      ++ [
        hddtemp
        hw-probe # note: 2024-06-25: weights ~560 MiB
        inxi
        lm_sensors
        lshw
        lsof
        pciutils # lspci
        sysfsutils # systool
        usbutils # lsusb
        util-linux # dmesg lsblk lscpu

        vulkan-caps-viewer
        vulkan-tools

        (lib.kdn.shell.writeShellScript pkgs ./bin/lsiommu.sh {
          runtimeInputs = with pkgs; [findutils];
        })
        (lib.kdn.shell.writeShellScript pkgs ./bin/gpu-passthrough-check.sh {
          runtimeInputs = with pkgs; [
            dmidecode
            util-linux # dmesg lsblk lscpu
            lshw
            pciutils # lspci
            usbutils # lsusb
            sysfsutils # systool
          ];
        })
        (lib.kdn.shell.writeShellScript pkgs ./bin/list-device-drivers.sh {
          # TODO: compgen: command not found
          runtimeInputs = with pkgs; [coreutils];
        })
        (lib.kdn.shell.writeShellScript pkgs ./bin/find-device-kernel-module.sh {
          runtimeInputs = with pkgs; [pciutils gnugrep];
        })

        stress-ng
      ];
  };
}
