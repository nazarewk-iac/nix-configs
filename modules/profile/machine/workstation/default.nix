{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.workstation;
in
{
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.profile.machine.desktop.enable = true;
    kdn.profile.machine.dev.enable = true;

    kdn.desktop.base.nixpkgs-wayland.enableFullOverlay = false;
    kdn.desktop.base.enableWlrootsPatch = false;

    kdn.sway.remote.enable = true;

    # do not suspend on GDM login screen (waiting for remote sessions etc.)
    services.xserver.displayManager.gdm.autoSuspend = false;

    kdn.hardware.edid.kernelOutputs = {
      # "DP-1" = "PG278Q_2014";
      # "DVI-D-1" = "U2711_2012_1";
    };

    environment.systemPackages = with pkgs; [
      nixos-anywhere
    ];

    hardware.cpu.amd.updateMicrocode = true;

    kdn.monitoring.prometheus-stack.enable = true;
    kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.networking.hostName}.kdn.im";
    kdn.monitoring.elasticsearch-stack.enable = true;
    kdn.monitoring.elasticsearch-stack.caddy.kibana = "kibana.${config.networking.hostName}.kdn.im";
    kdn.programs.caddy.enable = true;
    kdn.programs.obs-studio.enable = true;

    kdn.virtualization.libvirtd.enable = true;

    boot.initrd.availableKernelModules = [ ];

    kdn.virtualization.microvm.host.enable = false;
    microvm.vms.hello-microvm = { flake = self; };

    # CUSTOM

    kdn.desktop.remote-server.enable = true;
    kdn.hardware.edid.enable = true;
    kdn.programs.keepass.enable = true;
    kdn.programs.direnv.enable = true;
    kdn.programs.nix-index.enable = true;

    kdn.development.android.enable = true;
    kdn.containers.dagger.enable = true;
    kdn.containers.distrobox.enable = true;
    kdn.containers.podman.enable = true;
    kdn.containers.x11docker.enable = true;
    kdn.emulators.windows.enable = true;
    programs.seahorse.enable = true;
    boot.binfmt.emulatedSystems = [
      "aarch64-linux"
      "wasm32-wasi"
      "wasm64-wasi"
      "x86_64-windows"
    ];

    kdn.sway.gdm.enable = true;
    kdn.sway.systemd.enable = true;
  };
}
