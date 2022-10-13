# https://nixos.wiki/wiki/AMD_GPU
{ config, pkgs, lib, modulesPath, ... }:
{
  system.stateVersion = "22.05";
  networking.hostId = "81d86976"; # cut -c-8 </proc/sys/kernel/random/uuid
  networking.hostName = "nazarewk-krul";

  nazarewk.desktop.base.nixpkgs-wayland.enableFullOverlay = false;
  nazarewk.desktop.base.enableWlrootsPatch = false;

  nazarewk.sway.remote.enable = true;

  # do not suspend on GDM login screen (waiting for remote sessions etc.)
  services.xserver.displayManager.gdm.autoSuspend = false;

  nazarewk.hardware.edid.kernelOutputs = {
    # "DP-1" = "PG278Q_2014";
    # "DVI-D-1" = "U2711_2012_1";
  };

  hardware.cpu.amd.updateMicrocode = true;

  nazarewk.monitoring.prometheus-stack.enable = true;
  nazarewk.monitoring.prometheus-stack.caddy.grafana = "grafana.nazarewk.pw";
  nazarewk.monitoring.elasticsearch-stack.enable = true;
  nazarewk.monitoring.elasticsearch-stack.caddy.kibana = "kibana.nazarewk.pw";
  nazarewk.programs.caddy.enable = true;
  nazarewk.programs.obs-studio.enable = true;

  nazarewk.k3s.single-node.enable = false;
  nazarewk.k3s.single-node.enableTools = true;
  nazarewk.k3s.single-node.rook-ceph.enable = true;
  nazarewk.k3s.single-node.kube-prometheus.enable = true;
  nazarewk.k3s.single-node.istio.enable = true;
  nazarewk.k3s.single-node.zfsVolume = "nazarewk-krul-primary/nazarewk-krul/containers/containerd/io.containerd.snapshotter.v1.zfs";
  nazarewk.k3s.single-node.reservations.system.cpu = "4";
  nazarewk.k3s.single-node.reservations.system.memory = "32G";
  nazarewk.k3s.single-node.reservations.kube.cpu = "4";
  nazarewk.k3s.single-node.reservations.kube.memory = "4G";
  # nazarewk.development.podman.enable = true;

  nazarewk.virtualization.nixops.libvirtd.enable = true;

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
  ];

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
}
