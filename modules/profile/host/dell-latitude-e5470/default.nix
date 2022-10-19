{ config, pkgs, lib, modulesPath, waylandPkgs, ... }:
let
  cfg = config.kdn.profile.host.dell-latitude-e5470;
in
{
  options.kdn.profile.host.dell-latitude-e5470 = {
    enable = lib.mkEnableOption "enable dell-latitude-e5470 host profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;

    system.stateVersion = "21.05";
    networking.hostId = "f77614af"; # cut -c-8 </proc/sys/kernel/random/uuid
    networking.hostName = "nazarewk";

    kdn.sway.remote.enable = true;
    kdn.desktop.base.nixpkgs-wayland.enableFullOverlay = false;
    kdn.k3s.single-node.enableTools = true;
    kdn.filesystems.zfs-root.enable = true;
    # TODO: unlock hangs up on `ip=dhcp` when not connected to the router.
    # kdn.filesystems.zfs-root.sshUnlock.enable = true;
    environment.systemPackages = with pkgs; [
      google-chrome # easier on the CPU than Meet @ Firefox

      # hardware acceleration testing
      intel-gpu-tools
      (brave.override {
        commandLineArgs = ''
          --use-gl=egl \
          --ignore-gpu-blocklist \
          --enable-gpu-rasterization \
          --enable-zero-copy
        '';
        vulkanSupport = true;
      })
    ];

    kdn.hardware.intel-graphics-fix.enable = true;
    kdn.hardware.modem.enable = true;

    # BOOT
    boot.kernelParams = [ "consoleblank=90" ];
    boot.initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "uas"
      "rtsx_pci_sdmmc"
      "e1000e" # ethernet card
    ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.memtest86.enable = true;
    boot.cleanTmpDir = true;

    boot.kernel.sysctl = {
      "fs.inotify.max_user_watches" = 1048576; # default:  8192
      "fs.inotify.max_user_instances" = 1024; # default:   128
      "fs.inotify.max_queued_events" = 32768; # default: 16384
    };

    # Hardware configuration goes below

    fileSystems."/" = {
      device = "nazarewk-zroot/nazarewk/root";
      fsType = "zfs";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/34E7-0AA1";
      fsType = "vfat";
    };

    fileSystems."/home" = {
      device = "nazarewk-zroot/nazarewk/home";
      fsType = "zfs";
    };

    fileSystems."/home/nazarewk" = {
      device = "nazarewk-zroot/nazarewk/home/nazarewk";
      fsType = "zfs";
    };

    fileSystems."/home/nazarewk/.cache" = {
      device = "nazarewk-zroot/nazarewk/home/nazarewk/.cache";
      fsType = "zfs";
    };

    fileSystems."/home/nazarewk/Downloads" = {
      device = "nazarewk-zroot/nazarewk/home/nazarewk/Downloads";
      fsType = "zfs";
    };

    fileSystems."/home/nazarewk/Nextcloud" = {
      device = "nazarewk-zroot/nazarewk/home/nazarewk/Nextcloud";
      fsType = "zfs";
    };

    fileSystems."/nix" = {
      device = "nazarewk-zroot/local/nix";
      fsType = "zfs";
    };

    fileSystems."/var" = {
      device = "nazarewk-zroot/nazarewk/var";
      fsType = "zfs";
    };

    fileSystems."/var/log" = {
      device = "nazarewk-zroot/nazarewk/var/log";
      fsType = "zfs";
    };

    fileSystems."/var/log/journal" = {
      device = "nazarewk-zroot/nazarewk/var/log/journal";
      fsType = "zfs";
    };

    fileSystems."/tmp" = {
      device = "nazarewk-zroot/nazarewk/tmp";
      fsType = "zfs";
    };

    zramSwap.enable = true;
    zramSwap.memoryPercent = 50;
    zramSwap.priority = 100;

    swapDevices = [
      {
        device = "/dev/disk/by-partuuid/efd708db-6eb2-48ef-82c0-7760c1f3dd3e";
        priority = -10;
        randomEncryption.enable = true;
      }
    ];

    hardware.cpu.intel.updateMicrocode = true;
    boot.initrd.kernelModules = [ "dm-snapshot" "i915" ];
    # https://github.com/NixOS/nixos-hardware/blob/4045d5f43aff4440661d8912fc6e373188d15b5b/common/cpu/intel/default.nix
    hardware.opengl.extraPackages = with pkgs; [
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      vaapiVdpau
      libvdpau-va-gl
    ];

    nixpkgs.overlays = [
      (final: prev:
        {
          zoom-us = prev.runCommand "zoom-us-wrapper"
            {
              buildInputs = [ prev.makeWrapper ];
            } ''
            mkdir -p "$out/bin" "$out/share/applications"

            makeWrapper ${prev.zoom-us}/bin/zoom $out/bin/zoom --add-flags "--in-process-gpu"
            ln -s "$out/bin/zoom" "$out/bin/zoom-us"
            cp -a "${prev.zoom-us}/share" "$out/share"
            desktop_file="share/applications/Zoom.desktop"
            sed "s#${prev.zoom-us}#$out#g" "${prev.zoom-us}/$desktop_file" > "$out/$desktop_file"
          '';
          mako = waylandPkgs.mako;
        })
    ];
  };
}
