{ config, pkgs, lib, modulesPath, self, ... }:
let
  cfg = config.kdn.profile.host.oams;
in
{
  options.kdn.profile.host.oams = {
    enable = lib.mkEnableOption "enable oams host profile";
  };

  imports = [
    ./filesystem.nix
  ];

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;

    system.stateVersion = "22.11";
    networking.hostId = "8181cfa2"; # cut -c-8 </proc/sys/kernel/random/uuid
    networking.hostName = "oams";

    kdn.desktop.base.nixpkgs-wayland.enableFullOverlay = false;
    kdn.desktop.base.enableWlrootsPatch = false;

    kdn.sway.remote.enable = true;

    # do not suspend on GDM login screen (waiting for remote sessions etc.)
    services.xserver.displayManager.gdm.autoSuspend = false;

    kdn.hardware.edid.kernelOutputs = {
      # "DP-1" = "PG278Q_2014";
      # "DVI-D-1" = "U2711_2012_1";
    };

    hardware.cpu.amd.updateMicrocode = true;
    kdn.programs.caddy.enable = true;
    kdn.programs.obs-studio.enable = true;


    kdn.virtualization.nixops.libvirtd.enable = true;

    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.memtest86.enable = true;
    boot.loader.systemd-boot.configurationLimit = 20;

    boot.initrd.availableKernelModules = [
      "nvme" # NVMe disk
      "xhci_pci"
      "ahci"
      "usb_storage"
      "sd_mod"
      "r8169" # Realtek Semiconductor Co., Ltd. RTL8125 2.5GbE Controller [10ec:8125] (rev 05)
      "igb" # Intel Corporation I211 Gigabit Network Connection [8086:1539] (rev 03)
    ];
    boot.initrd.kernelModules = [ "amdgpu" "kvm-amd" ];
    services.xserver.videoDrivers = [ "amdgpu" ];

    hardware.opengl.enable = true;
    hardware.opengl.extraPackages = with pkgs; [
      amdvlk
      rocm-opencl-icd
      rocm-opencl-runtime
    ];
    hardware.opengl.extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];
    hardware.opengl.driSupport = true;
    hardware.opengl.driSupport32Bit = true;

    environment.systemPackages = with pkgs; [
      radeontop
    ];

    # networking.interfaces.enp5s0.wakeOnLan.enable = true;
    # networking.interfaces.enp6s0.wakeOnLan.enable = true;

    kdn.virtualization.microvm.host.enable = true;
  };
}
