{ config, pkgs, lib, ... }:
let
  cfg = config.kdn.profile.host.oams;
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home-manager.users.kdn.programs.firefox.profiles.kdn.path = "v6uzqa6m.default";
      home-manager.users.kdn.home.file.".mozilla/firefox/profiles.ini".force = true;

      kdn.profile.machine.workstation.enable = true;
      kdn.hardware.gpu.amd.enable = true;
      kdn.hardware.cpu.amd.enable = true;

      kdn.profile.machine.gaming.enable = true;
      kdn.hardware.gpu.vfio.enable = lib.mkForce false;
      kdn.hardware.gpu.vfio.gpuIDs = [
        "1002:73df"
        "1002:ab28"
      ];

      systemd.tmpfiles.rules = [
        "f /dev/shm/looking-glass 0660 kdn qemu-libvirtd -"
      ];

      kdn.filesystems.disko.luks-zfs.enable = true;
      disko.devices = import ./disko.nix {
        inherit lib;
        hostname = config.networking.hostName;
        inMicroVM = config.kdn.virtualization.microvm.guest.enable;
      };

      boot.initrd.systemd.services.zfs-import-oams-main = {
        requiredBy = [ "sysusr-usr.mount" ];
        before = [ "sysusr-usr.mount" ];
      };

      boot.kernelModules = [ "kvm-amd" ];

      services.asusd.enable = true;
      kdn.hardware.gpu.multiGPU.enable = true;
      services.asusd.enableUserService = false; # just strobes the LEDs, better turn it off
      environment.systemPackages = with pkgs; [
        asusctl
      ];
      home-manager.sharedModules = [{
        wayland.windowManager.sway.extraConfig = ''
          output eDP-1 mode 2560x1440@60Hz
        '';
      }];
    }
  ]);
}
