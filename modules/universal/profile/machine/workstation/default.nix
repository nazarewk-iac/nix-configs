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
        kdn.desktop.remote-server.enable = lib.mkDefault true;
        kdn.desktop.sway.enable = lib.mkDefault true;
        kdn.desktop.sway.remote.enable = lib.mkDefault true;
        kdn.development.android.enable = lib.mkDefault true;
        kdn.development.kernel.enable = false;
        kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.kdn.hostName}.kdn.im";
        kdn.monitoring.prometheus-stack.enable = false;
        kdn.profile.machine.desktop.enable = lib.mkDefault true;
        kdn.profile.machine.dev.enable = lib.mkDefault true;
        kdn.programs.editors.photo.enable = lib.mkDefault true;
        kdn.programs.editors.video.enable = lib.mkDefault true;
        kdn.programs.gnupg.pinentry = pkgs.kdn.pinentry;
        kdn.programs.nix-index.enable = lib.mkDefault true;
        kdn.programs.obs-studio.enable = lib.mkDefault true;
        kdn.services.caddy.enable = false;
        kdn.services.k8s.management.enable = lib.mkDefault true;
        kdn.toolset.diagrams.enable = lib.mkDefault true;
        kdn.toolset.logs-processing.enable = lib.mkDefault true;
        kdn.virtualisation.libvirtd.enable = lib.mkDefault true;
        kdn.virtualisation.vagrant.enable = lib.mkDefault true;
      }
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            boot.initrd.availableKernelModules = [ ];
            programs.seahorse.enable = lib.mkDefault true;
            boot.binfmt.emulatedSystems = [
              # "wasm32-wasi"
              # "wasm64-wasi"
            ];

            services.offlineimap.install = lib.mkDefault true;
            kdn.networking.tailscale.auth_key = "nixos-kdn";
          }
          {
            boot.initrd.clevis.enable = lib.mkDefault true;
          }
        ]
      ))
    ]
  );
}
