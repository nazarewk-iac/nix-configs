{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.kdn.profile.host.moss;
in {
  options.kdn.profile.host.moss = {
    enable = lib.mkEnableOption "enable moss host profile";
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.profile.machine.hetzner.enable = true;
      kdn.profile.machine.hetzner.ipv6Address = "2a01:4f8:1c0c:56e4::1/64";
      security.sudo.wheelNeedsPassword = false;

      # TODO: anji times out on using moss as DNS resolver (port 5353)
      kdn.profile.machine.baseline.multicastDNS = "false";
    }
  ]);
}
