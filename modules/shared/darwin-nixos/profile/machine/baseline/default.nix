{
  lib,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.openssh.enable = true;
      environment.etc."kdn/source-flake".source = kdnConfig.self;
      nix.gc.automatic = true;
      # angrr seems to drop all of the sources regularly, maybe I could integrate `angrr touch` to prevent this?
      services.angrr.enable = true;
      services.angrr.period = "2weeks";
    }
    (kdnConfig.util.ifTypes ["nixos"] {
      services.angrr.enableNixGcIntegration = true;
    })
  ]);
}
