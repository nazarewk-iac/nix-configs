{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.gpu;
in
{
  options.kdn.hardware.gpu = {
    multiGPU.enable = lib.mkEnableOption "multiple GPUs setup";
    vfio = {
      enable = lib.mkEnableOption "VFIO setup";
      gpuIDs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.multiGPU.enable {
      services.supergfxd.enable = true;
      services.switcherooControl.enable = true;
      systemd.services.supergfxd.path = [ pkgs.kmod ];
      environment.systemPackages = with pkgs; [
        supergfxctl
      ];
      boot.kernelParams = lib.concatLists [
        (lib.lists.optional config.kdn.hardware.gpu.amd.enable "supergfxd.mode=integrated")
      ];
    })
    (lib.mkIf cfg.vfio.enable {
      # see https://astrid.tech/2022/09/22/0/nixos-gpu-vfio/
      boot.initrd.kernelModules = [
        "vfio_pci"
        "vfio"
        "vfio_iommu_type1"
        "vfio_virqfd"
      ];

      # see https://gist.github.com/k-amin07/47cb06e4598e0c81f2b42904c6909329#isolating-gpu
      boot.extraModprobeConfig = ''
        softdep amdgpu pre: vfio-pci
        softdep snd_hda_intel pre: vfio-pci
      '';
      boot.kernelParams = lib.concatLists [
        (lib.lists.optional config.kdn.hardware.cpu.amd.enable "amd_iommu=on")
        (lib.lists.optional config.kdn.hardware.cpu.intel.enable "intel_iommu=on")
        [ "iommu=pt" ]
        (lib.lists.optional (cfg.vfio.gpuIDs != [ ]) ("vfio-pci.ids=" + lib.concatStringsSep "," cfg.vfio.gpuIDs))
      ];
    })
  ];
}
