{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
    kdnConfig.inputs.nixos-crostini.nixosModules.baguette
  ];

  config = lib.mkMerge [
    {
      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "91e34e17"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      # Baguette tweaks
      kdn.networking.resolved.enable = false;
      services.resolved.enable = false;
      boot.loader.systemd-boot.enable = false;
      virtualisation.buildMemorySize = 16 * 1024;
      virtualisation.diskImageSize = 20 * 1024;
    }
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.profile.machine.dev.enable = false;
    }
    {
      # thin out dependencies

      kdn.desktop.enable = false;
      kdn.profile.machine.desktop.enable = false;
      kdn.development.llm.online.enable = false;
    }
    # TODO: add SSH host keys (using kdnctl?)
    {
      # relax some settings for easier debugging
      services.openssh.settings.PasswordAuthentication = true;
      services.openssh.ports = [22 2323];
      security.sudo.wheelNeedsPassword = false;
    }
    {
      networking.firewall.trustedInterfaces = ["nb-priv" "eth0"];
      networking.firewall.enable = lib.mkForce true;
    }
  ];
}
