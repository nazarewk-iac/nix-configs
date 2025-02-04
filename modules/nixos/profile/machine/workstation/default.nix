{
  lib,
  pkgs,
  config,
  self,
  ...
}: let
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

      kdn.virtualization.microvm.host.enable = false;
      microvm.vms.hello-microvm = {flake = self;};

      # CUSTOM

      kdn.desktop.remote-server.enable = true;
      kdn.programs.nix-index.enable = true;

      kdn.development.android.enable = true;
      kdn.development.kernel.enable = false;
      #kdn.virtualisation.containers.dagger.enable = true;
      #kdn.virtualisation.containers.distrobox.enable = true;
      kdn.virtualisation.containers.enable = true;
      kdn.virtualisation.containers.podman.enable = true;
      kdn.virtualisation.containers.talos.enable = false;
      #kdn.virtualisation.containers.x11docker.enable = true;
      programs.seahorse.enable = true;
      boot.binfmt.emulatedSystems = [
        "aarch64-linux"
        "wasm32-wasi"
        "wasm64-wasi"
        /*
        2024-03-11:
        error: builder for '/nix/store/sd233q3n28m8qkzq210yn5xpmy1pplqr-wine64-9.0.drv' failed with exit code 1;
               last 10 log lines:
               > checking for x86_64-w64-mingw32-clang... no
               > checking for amd64-w64-mingw32-clang... no
               > checking for clang... no
               > checking for pthread_create... yes
               > checking how to run the C preprocessor... gcc -m64 -E
               > checking for X... no
               > configure: error: X 64-bit development files not found. Wine will be built
               > without X support, which probably isn't what you want. You will need
               > to install 64-bit development packages of Xlib at the very least.
               > Use the --without-x option if you really want this.
               For full logs, run 'nix log /nix/store/sd233q3n28m8qkzq210yn5xpmy1pplqr-wine64-9.0.drv'.
        */
        # "x86_64-windows"
        # "i686-windows"
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
