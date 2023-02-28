{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.virtualization.libvirtd;
in
{
  options.kdn.virtualization.libvirtd = {
    enable = lib.mkEnableOption "libvirtd setup";
  };

  config = lib.mkIf cfg.enable {
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
  };
}
