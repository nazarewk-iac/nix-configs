{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.gnupg.forwarding;
  client = cfg.client;
  server = cfg.server;
in
{
  # based on:
  # - https://flameeyes.blog/2016/10/15/gnupg-agent-forwarding-with-openpgp-cards/
  # - https://wiki.gnupg.org/AgentForwarding
  options.nazarewk.programs.gnupg.forwarding = { };

  options.nazarewk.programs.gnupg.forwarding.client = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
  };

  options.nazarewk.programs.gnupg.forwarding.server = {
    enable = mkEnableOption "GnuPG forwarding from remote systems";
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      nazarewk.programs.gnupg.enable = true;
    })
    (mkIf cfg.server.enable {
      nazarewk.programs.gnupg.enable = true;
    })
  ];
}
