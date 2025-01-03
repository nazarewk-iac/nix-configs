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

    lookingGlass = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      instances = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.hardware.gpu.vfio.enable = lib.mkDefault true;
      virtualisation.spiceUSBRedirection.enable = true;
      # see https://nixos.wiki/wiki/Virt-manager
      # see https://nixos.wiki/wiki/Libvirt
      virtualisation.libvirtd = {
        enable = true;
        #qemu.package = pkgs.qemu_full; # 2024-01-23 fails while building ceph, see https://github.com/NixOS/nixpkgs/issues/281027
        qemu.package = pkgs.qemu;
        qemu.swtpm.enable = true;
        qemu.ovmf = {
          enable = true;
          packages = [
            pkgs.OVMFFull.fd
            # TODO: wait to resolve https://github.com/NixOS/nixpkgs/issues/245188
            #pkgs.pkgsCross.aarch64-multiplatform.OVMF.fd
          ];
        };
      };
      kdn.programs.dconf.enable = true;
      networking.firewall.checkReversePath = false;
      networking.networkmanager.unmanaged = ["interface-name:virbr*"];

      /*
         TODO: wait for VM packaging? https://github.com/NixOS/nixpkgs/issues/287644
      services.cockpit.enable = true;
      */
      environment.systemPackages = with pkgs; [
        libguestfs
        libvirt
        virt-manager
        virtiofsd
        cloud-utils # cloud-localds for https://blog.programster.org/create-ubuntu-22-kvm-guest-from-cloud-image
      ];
    }
    {
      environment.persistence."usr/data".directories = [
        "/var/lib/libvirt/images"
        "/var/lib/libvirt"
        "/var/lib/swtpm-localca"
      ];
    }
    (lib.mkIf cfg.lookingGlass.enable {
      environment.systemPackages = with pkgs; [
        # looking-glass-client  # TODO: doesn't work https://github.com/NixOS/nixpkgs/issues/368827
        scream
      ];

      systemd.tmpfiles.rules = lib.trivial.pipe cfg.lookingGlass.instances [
        (lib.attrsets.mapAttrsToList (name: username: [
          # "f /dev/shm/${name}-looking-glass 0660 ${username} qemu-libvirtd -"
          "f /dev/shm/${name}-scream 0660 ${username} qemu-libvirtd -"
        ]))
        lib.lists.flatten
      ];

      # TODO: instantiate scream for user
      #systemd.services = lib.attrsets.mapAttrs'
      #  (name: username: lib.attrsets.nameValuePair
      #    "scream-ivshmem-${name}"
      #    {
      #      description = "Scream IVSHMEM for ${name}";
      #      serviceConfig = {
      #        ExecStart = "${pkgs.scream}/bin/scream -m /dev/shm/${name}-scream -o pulse -n ${name}-scream";
      #        Restart = "always";
      #      };
      #      wantedBy = [ "default.target" ];
      #      requires = [ "pipewire.service" ];
      #    })
      #  cfg.lookingGlass.instances;
    })
  ]);
}
