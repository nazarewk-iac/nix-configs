{
  lib,
  config,
  kdnConfig,
  ...
}: let
  cfg = config.kdn.profile.machine.baseline;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.etc."kdn/source-flake".source = kdnConfig.self;
      }
    ]
  );
}
