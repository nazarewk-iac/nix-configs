{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.profile.machine.workstation;
in
{
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [ { kdn.profile.machine.workstation = lib.mkDefault cfg; } ];
      })
      {
        kdn.env.packages = with pkgs; [
          diffoscope
        ];
      }
      {
        kdn.desktop.kde.enable = false;
        kdn.desktop.remote-server.enable = true;
        kdn.desktop.sway.enable = true;
        kdn.desktop.sway.remote.enable = true;
        kdn.development.android.enable = true;
        kdn.development.kernel.enable = false;
        kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.kdn.hostName}.kdn.im";
        kdn.monitoring.prometheus-stack.enable = false;
        kdn.profile.machine.desktop.enable = true;
        kdn.profile.machine.dev.enable = true;
        kdn.programs.editors.photo.enable = true;
        kdn.programs.editors.video.enable = true;
        kdn.programs.gnupg.pinentry = pkgs.kdn.pinentry;
        kdn.programs.nix-index.enable = true;
        kdn.programs.obs-studio.enable = true;
        kdn.services.caddy.enable = false;
        kdn.services.k8s.management.enable = true;
        kdn.toolset.diagrams.enable = true;
        kdn.toolset.logs-processing.enable = true;
        kdn.virtualisation.containers.enable = true;
        kdn.virtualisation.containers.podman.enable = true;
        kdn.virtualisation.libvirtd.enable = true;
        kdn.virtualisation.vagrant.enable = true;
      }
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            boot.initrd.availableKernelModules = [ ];
            programs.seahorse.enable = true;
            boot.binfmt.emulatedSystems = [
              "wasm32-wasi"
              "wasm64-wasi"
            ];

            services.offlineimap.install = true;
            kdn.networking.tailscale.auth_key = "nixos-kdn";
          }
          {
            boot.initrd.clevis.enable = true;
          }
        ]
      ))
    ]
  );
}
