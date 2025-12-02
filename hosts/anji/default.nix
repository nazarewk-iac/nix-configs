{
  lib,
  config,
  pkgs,
  kdnConfig,
  ...
}: {
  imports = [
    kdnConfig.self.darwinModules.default
  ];

  config = lib.mkMerge [
    {
    kdn.hostName = "anji";
      kdn.profile.machine.baseline.enable = true;
    }
    {
      nixpkgs.system = "aarch64-darwin";
      system.stateVersion = 6;
      home-manager.sharedModules = [{home.stateVersion = "26.05";}];
    }
    {
      kdn.nix.remote-builder.enable = true;
      environment.systemPackages = with pkgs; [
        utm
      ];
    }
  ];
}
