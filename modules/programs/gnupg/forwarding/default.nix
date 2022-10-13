{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.kdn.programs.gnupg.forwarding;
  client = cfg.client;
  server = cfg.server;
in
{
  # based on:
  # - https://flameeyes.blog/2016/10/15/gnupg-agent-forwarding-with-openpgp-cards/
  # - https://wiki.gnupg.org/AgentForwarding
  options.kdn.programs.gnupg.forwarding = { };

  options.kdn.programs.gnupg.forwarding.client = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
  };

  options.kdn.programs.gnupg.forwarding.server = {
    enable = mkEnableOption "GnuPG forwarding from remote systems";
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      kdn.programs.gnupg.enable = true;
    })
    (mkIf cfg.server.enable {
      kdn.programs.gnupg.enable = true;
    })
  ];
}
