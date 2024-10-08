{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.hardware.gpu;
in
{
  options.kdn.hardware.gpu = {
    enable = lib.mkEnableOption "GPU setup";
    multiGPU.enable = lib.mkEnableOption "multiple GPUs setup";
    vfio.enable = lib.mkEnableOption "VFIO setup";
    vfio.gpuIDs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      hardware.graphics.enable = true;
    }
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
        # "vfio_virqfd" # in 6.2+ part of kernel, see https://www.reddit.com/r/archlinux/comments/11dqiy5/vfio_virqfd_missing_in_linux621arch11/
      ];

      # see https://gist.github.com/k-amin07/47cb06e4598e0c81f2b42904c6909329#isolating-gpu
      boot.extraModprobeConfig = ''
        softdep amdgpu pre: vfio-pci
        softdep snd_hda_intel pre: vfio-pci
      '';
      boot.kernelParams = lib.concatLists [
        # see https://docs.kernel.org/admin-guide/kernel-parameters.html?highlight=amd_iommu
        #(lib.lists.optionals config.kdn.hardware.cpu.amd.enable [ "amd_iommu=on" ]) # supposedly on by default
        (lib.lists.optional config.kdn.hardware.cpu.intel.enable "intel_iommu=on")
        [ "iommu=pt" ]
        (lib.lists.optional (cfg.vfio.gpuIDs != [ ]) ("vfio-pci.ids=" + lib.concatStringsSep "," cfg.vfio.gpuIDs))
      ];
    })
  ]);
}
