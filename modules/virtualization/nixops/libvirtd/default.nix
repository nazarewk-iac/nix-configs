{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.virtualization.nixops.libvirtd;
in
{
  options.kdn.virtualization.nixops.libvirtd = {
    enable = lib.mkEnableOption "libvirtd nixops setup";
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd.enable = true;
    networking.firewall.checkReversePath = false;

    environment.systemPackages = with pkgs; [
      virt-manager
      config.virtualisation.libvirtd.qemu.package
    ];

    system.activationScripts.nazarewkLibVirtdInit =
      let
        virsh = "${config.virtualisation.libvirtd.package}/bin/virsh";
      in
      ''
        libvirt=/var/lib/libvirt
        libvirt_pool=default
        libvirt_images="$libvirt/images"

        mkdir -p "$libvirt_images"
        chgrp -R libvirtd "$libvirt"
        chmod -R g+w "$libvirt"

        if ! ${virsh} pool-info "$libvirt_pool" >/dev/null ; then
          ${virsh} pool-define-as "$libvirt_pool" dir --target "$libvirt_images"
        fi
        if ${virsh} pool-info "$libvirt_pool" | grep '^Autostart: *no$' >/dev/null ; then
          if ${virsh} pool-info "$libvirt_pool" | grep '^State: *running$' >/dev/null ; then
            ${virsh} pool-destroy "$libvirt_pool"
          fi
          ${virsh} pool-autostart "$libvirt_pool"
        fi
        if ! ${virsh} pool-info "$libvirt_pool" | grep '^State: *running$' >/dev/null ; then
          ${virsh} pool-start "$libvirt_pool"
        fi
      '';
  };
}
