{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.workstation;
in
{
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [{
    kdn.desktop.kde.enable = false;
    kdn.desktop.sway.enable = true;
    kdn.desktop.sway.remote.enable = true;

    kdn.programs.gnupg.pinentry = pkgs.kdn.pinentry;

    kdn.profile.machine.desktop.enable = true;
    kdn.profile.machine.dev.enable = true;

    kdn.monitoring.prometheus-stack.enable = false;
    kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.networking.hostName}.kdn.im";
    kdn.services.caddy.enable = true;
    kdn.programs.obs-studio.enable = true;

    kdn.virtualization.libvirtd.enable = true;

    boot.initrd.availableKernelModules = [ ];

    kdn.virtualization.microvm.host.enable = false;
    microvm.vms.hello-microvm = { flake = self; };

    # CUSTOM

    kdn.desktop.remote-server.enable = true;
    kdn.programs.keepass.enable = true;
    kdn.programs.direnv.enable = true;
    kdn.programs.nix-index.enable = true;

    kdn.development.android.enable = true;
    kdn.development.kernel.enable = true;
    #kdn.virtualisation.containers.dagger.enable = true;
    #kdn.virtualisation.containers.distrobox.enable = true;
    kdn.virtualisation.containers.enable = true;
    kdn.virtualisation.containers.podman.enable = true;
    # TODO: enable after fixed https://github.com/NixOS/nixpkgs/issues/264127
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

    services.netbird.clients.sc.autoStart = false;
    services.netbird.clients.sc.port = 51818;

    kdn.networking.openvpn.enable = true;
    kdn.networking.openfortivpn.enable = true;
    kdn.networking.openvpn.debug = true;
    kdn.networking.openvpn.instances = {
      goggles-humongous = {
        routes.add = [
          { network = "10.40.0.0"; netmask = "255.255.0.0"; }
        ];
      };
      chance-acuteness = { };
      senorita-recant = {
        routes.ignore = true;
        routes.add = [
          { network = "10.33.0.0"; netmask = "255.255.0.0"; }
          { network = "10.34.0.0"; netmask = "255.255.0.0"; }
          { network = "10.44.0.0"; netmask = "255.255.0.0"; }
          { network = "192.168.107.0"; netmask = "255.255.255.0"; }
        ];
      };
      fracture-outage = {
        routes.ignore = true;
        routes.add = [
          { network = "172.16.0.0"; netmask = "255.255.0.0"; }
          { network = "172.18.0.0"; netmask = "255.255.0.0"; }
        ];
      };
      scientist-properly = {
        routes.ignore = true;
        routes.add = [
          { network = "10.241.0.0"; netmask = "255.255.0.0"; }
        ];
      };
      baguette-geology = { };
    };
  }
    {
      boot.initrd.clevis.enable = true;
    }]);
}
