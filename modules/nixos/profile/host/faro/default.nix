{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.faro;
in {
  options.kdn.profile.host.faro = {
    enable = lib.mkEnableOption "enable faro host profile (running as a VM on `anji`)";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.nix.remote-builder.enable = true;
      security.sudo.wheelNeedsPassword = false;
    }
  ]);
}
