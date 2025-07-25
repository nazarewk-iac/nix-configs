{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.virtualization.libvirtd;
in {
  options.kdn.virtualization.libvirtd = {
    enable = lib.mkEnableOption "libvirtd setup";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.hw.gpu.vfio.enable = lib.mkDefault true;
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
        qemu.vhostUserPackages = with pkgs; [
          virtiofsd
        ];
      };
      kdn.programs.dconf.enable = true;
      networking.firewall.checkReversePath = false;
      networking.networkmanager.unmanaged = ["interface-name:virbr*"];
      # TODO: is it needed?
      networking.firewall.trustedInterfaces = ["virbr*"];
      /*
         TODO: wait for VM packaging? https://github.com/NixOS/nixpkgs/issues/287644
      services.cockpit.enable = true;
      */
      environment.systemPackages = with pkgs; [
        guestfs-tools
        libguestfs
        libvirt
        virt-manager
        cloud-utils # cloud-localds for https://blog.programster.org/create-ubuntu-22-kvm-guest-from-cloud-image
      ];
    }
    /*
    This didn't work out in the end
    {
    # stable paths for Windows 11 VMs (UEFI), see for context https://kagi.com/assistant/9ca4ce35-25c7-425d-8f8a-65feeb67e106
      systemd.tmpfiles.rules = [
        "L+ /var/lib/qemu/share           - - - - ${config.virtualisation.libvirtd.qemu.package}/share/qemu"
      ];
    }
    */
    {
      kdn.hw.disks.persist."usr/data".directories = [
        "/var/lib/libvirt/images"
        "/var/lib/libvirt"
        "/var/lib/swtpm-localca"
      ];
      home-manager.sharedModules = [
        {
          kdn.hw.disks.persist."usr/data".directories = [
            ".local/share/images"
          ];
          home.file.".local/share/images/virtio-win".source = pkgs.virtio-win;
        }
      ];
    }
  ]);
}
