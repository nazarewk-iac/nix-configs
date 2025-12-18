{
  config,
  pkgs,
  lib,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.nixosModules.default
    kdnConfig.inputs.nixos-avf.nixosModules.avf
  ];

  config = lib.mkMerge [
    {
      kdn.hostName = "orr";

      system.stateVersion = "26.05";
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
      networking.hostId = "b2601b4f"; # cut -c-8 </proc/sys/kernel/random/uuid
    }
    {
      # preserving nixos-avf networking tweaks
      networking.networkmanager.enable = false;
      services.avahi.enable = true;
      services.resolved.llmnr = "false";
      kdn.networking.resolved.multicastDNS = "false";

      # turn off some incompatible features
    }
    {
      kdn.profile.machine.baseline.enable = true;
      kdn.profile.machine.dev.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }

    {
      # thin out dependencies

      kdn.desktop.enable = false;
      kdn.profile.machine.desktop.enable = false;
      kdn.development.llm.online.enable = false;
    }
    # TODO: add SSH host keys (using kdnctl?)
  ];
}
