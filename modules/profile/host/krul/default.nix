{ config, pkgs, lib, modulesPath, ... }:
let
  cfg = config.kdn.profile.host.krul;
in
{
  options.kdn.profile.host.krul = {
    enable = lib.mkEnableOption "enable krul host profile";
  };

  imports = [
    ./filesystem.nix
  ];

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;

    system.stateVersion = "22.11";
    networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
    networking.hostName = "nazarewk-krul";

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

    kdn.monitoring.prometheus-stack.enable = true;
    kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.kdn.pw";
    kdn.monitoring.elasticsearch-stack.enable = true;
    kdn.monitoring.elasticsearch-stack.caddy.kibana = "kibana.kdn.pw";
    kdn.programs.caddy.enable = true;
    kdn.programs.obs-studio.enable = true;

    kdn.k3s.single-node.enable = false;
    kdn.k3s.single-node.enableTools = true;
    kdn.k3s.single-node.rook-ceph.enable = true;
    kdn.k3s.single-node.kube-prometheus.enable = true;
    kdn.k3s.single-node.istio.enable = true;
    kdn.k3s.single-node.zfsVolume = "nazarewk-krul-primary/nazarewk-krul/containers/containerd/io.containerd.snapshotter.v1.zfs";
    kdn.k3s.single-node.reservations.system.cpu = "4";
    kdn.k3s.single-node.reservations.system.memory = "32G";
    kdn.k3s.single-node.reservations.kube.cpu = "4";
    kdn.k3s.single-node.reservations.kube.memory = "4G";
    # kdn.development.podman.enable = true;

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

    networking.interfaces.enp5s0.wakeOnLan.enable = true;
    networking.interfaces.enp6s0.wakeOnLan.enable = true;
  };
}
