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

    system.stateVersion = "23.05";

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

    kdn.virtualization.nixops.libvirtd.enable = true;

    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.memtest86.enable = true;
    boot.loader.systemd-boot.configurationLimit = 20;

    boot.initrd.availableKernelModules = [ ];

    kdn.virtualization.microvm.host.enable = false;
    microvm.vms.hello-microvm = { flake = self; };

    # CUSTOM

    programs.steam.enable = true;

    kdn.desktop.remote-server.enable = true;
    kdn.hardware.discovery.enable = true;
    kdn.hardware.edid.enable = true;
    kdn.programs.keepass.enable = true;
    kdn.programs.nix-direnv.enable = true;
    kdn.programs.nix-index.enable = true;
  };
}
