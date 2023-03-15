{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.virtualization.libvirtd;
in
{
  options.kdn.virtualization.libvirtd = {
    enable = lib.mkEnableOption "libvirtd setup";
    vfio = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      gpuIDs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      virtualisation.spiceUSBRedirection.enable = true;
      # see https://nixos.wiki/wiki/Virt-manager
      # see https://nixos.wiki/wiki/Libvirt
      virtualisation.libvirtd = {
        enable = true;
        qemu.package = pkgs.qemu_full;
        qemu.swtpm.enable = true;
        qemu.ovmf = {
          enable = true;
          packages = [
            pkgs.OVMFFull.fd
            pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd
          ];
        };
      };
      programs.dconf.enable = true;
      networking.firewall.checkReversePath = false;


      environment.systemPackages = with pkgs; [
        libguestfs
        libvirt
        virt-manager
        virtiofsd
      ];
    }
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

      specialisation."VFIO".configuration = {
        system.nixos.tags = [ "with-vfio" ];
        boot.kernelParams = lib.concatLists [
          (lib.lists.optional config.kdn.hardware.gpu.amd.enable "supergfxd.mode=vfio")
          (lib.lists.optional config.kdn.hardware.cpu.amd.enable "amd_iommu=on")
          (lib.lists.optional config.kdn.hardware.cpu.intel.enable "intel_iommu=on")
          [ "iommu=pt" ]
          (lib.lists.optional (cfg.vfio.gpuIDs != [ ]) ("vfio-pci.ids=" + lib.concatStringsSep "," cfg.vfio.gpuIDs))
        ];
      };
    })
  ]);
}
