{ lib, pkgs, config, self, ... }:
let
  cfg = config.kdn.profile.machine.workstation;
in
{
  options.kdn.profile.machine.workstation = {
    enable = lib.mkEnableOption "enable workstation machine profile";
  };

  config = lib.mkIf cfg.enable {
    kdn.desktop.kde.enable = false;
    kdn.desktop.sway.enable = true;
    kdn.desktop.sway.remote.enable = true;

    home-manager.users.kdn = {
      # while debugging pinentry wrapper
      home.file.".gnupg/gpg-agent.conf".force = true;
    };
    kdn.programs.gnupg.pinentry = pkgs.kdn.pinentry;

    kdn.profile.machine.desktop.enable = true;
    kdn.profile.machine.dev.enable = true;

    environment.systemPackages = with pkgs; [
    ];

    hardware.cpu.amd.updateMicrocode = true;

    kdn.monitoring.prometheus-stack.enable = true;
    kdn.monitoring.prometheus-stack.caddy.grafana = "grafana.${config.networking.hostName}.kdn.im";
    kdn.programs.caddy.enable = true;
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
      "x86_64-windows"
    ];


    # services.offlineimap.enable or manually with `systemctl --user start`
    services.offlineimap.install = true;

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
  };
}
