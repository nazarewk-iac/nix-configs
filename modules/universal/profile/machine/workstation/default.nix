{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.workstation;
in {
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (kdnConfig.util.ifHMParent {home-manager.sharedModules = [{kdn.profile.machine.workstation.enable = true;}];})
    {
      kdn.toolset.diagrams.enable = true;
      kdn.services.k8s.management.enable = true;
    }
    (kdnConfig.util.ifTypes ["nixos"] (lib.mkMerge [
      {
        kdn.desktop.kde.enable = false;
        kdn.desktop.sway.enable = true;
        kdn.desktop.sway.remote.enable = true;

        kdn.programs.gnupg.pinentry = pkgs.kdn.pinentry;

        kdn.profile.machine.desktop.enable = true;
        kdn.profile.machine.dev.enable = true;

        kdn.monitoring.prometheus-stack.enable = false;
        kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.kdn.hostName}.kdn.im";
        kdn.services.caddy.enable = false;
        kdn.programs.obs-studio.enable = true;

        kdn.virtualisation.libvirtd.enable = true;
        kdn.virtualisation.vagrant.enable = true;

        boot.initrd.availableKernelModules = [];

        kdn.desktop.remote-server.enable = true;
        kdn.programs.nix-index.enable = true;

        kdn.development.android.enable = true;
        kdn.development.kernel.enable = false;
        kdn.virtualisation.containers.enable = true;
        kdn.virtualisation.containers.podman.enable = true;
        programs.seahorse.enable = true;
        boot.binfmt.emulatedSystems = [
          "wasm32-wasi"
          "wasm64-wasi"
        ];

        kdn.programs.editors.photo.enable = true;
        kdn.programs.editors.video.enable = true;

        services.offlineimap.install = true;

        kdn.networking.tailscale.auth_key = "nixos-kdn";
      }
      {
        boot.initrd.clevis.enable = true;
      }
      {
        kdn.toolset.logs-processing.enable = true;
        environment.systemPackages = with pkgs; [
          diffoscope
        ];
      }
      {
        kdn.networking.netbird.clients.t1.enable = true;
        kdn.networking.netbird.clients.t2.enable = true;
        kdn.networking.netbird.clients.t3.enable = true;
      }
    ]))
  ]);
}
