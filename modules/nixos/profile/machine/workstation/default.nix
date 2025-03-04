{
  lib,
  pkgs,
  config,
  kdn,
  ...
}: let
  inherit (kdn) self;
  cfg = config.kdn.profile.machine.workstation;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
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

      kdn.virtualization.libvirtd.enable = true;

      boot.initrd.availableKernelModules = [];

      # CUSTOM

      kdn.desktop.remote-server.enable = true;
      kdn.programs.nix-index.enable = true;

      kdn.development.android.enable = true;
      kdn.development.kernel.enable = false;
      #kdn.virtualisation.containers.dagger.enable = true;
      #kdn.virtualisation.containers.distrobox.enable = true;
      kdn.virtualisation.containers.enable = true;
      kdn.virtualisation.containers.podman.enable = true;
      #kdn.virtualisation.containers.x11docker.enable = true;
      programs.seahorse.enable = true;
      boot.binfmt.emulatedSystems = [
        "aarch64-linux" # got dedicated builders now, but: a 'aarch64-linux' with features {} is required to build '/nix/store/r2rc0jhz761xmyc7w4zyl5v1ayx41hg0-converted-kdn-sops-nix-anonymization.paths.json.drv', but I am a 'x86_64-linux' with features {benchmark, big-parallel, kvm, nixos-test}
        "wasm32-wasi"
        "wasm64-wasi"
      ];

      kdn.programs.editors.photo.enable = true;
      kdn.programs.editors.video.enable = true;

      # services.offlineimap.enable or manually with `systemctl --user start`
      services.offlineimap.install = true;

      kdn.networking.tailscale.auth_key = "nixos-kdn";
    }
    {
      boot.initrd.clevis.enable = true;
    }
    {
      environment.systemPackages = with pkgs; [
        /*
        Closure is freaking 9 GB!
           /nix/store/16bffw12fg6jixyal4mn2cknv88rafwg-diffoscope-269
           NAR Size: 2.27 MiB | Closure Size: 8.73 GiB | Added Size: 8.73 GiB
           Immediate Parents: -
        */
        diffoscope
      ];
    }
  ]);
}
