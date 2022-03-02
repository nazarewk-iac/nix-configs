{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.programs.gnupg.forwarding;
  client = cfg.client;
  server = cfg.server;
in {
  # based on:
  # - https://flameeyes.blog/2016/10/15/gnupg-agent-forwarding-with-openpgp-cards/
  # - https://wiki.gnupg.org/AgentForwarding
  options.nazarewk.programs.gnupg.forwarding = {
    socketPath = mkOption {
      default = ".gnupg/S.gpg-agent";
    };
  };
  options.nazarewk.programs.gnupg.forwarding.client = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
    user = mkOption {
      default = server.user;
    };
    socketPath =  mkOption {
      default = "${cfg.socketPath}.local";
    };
    sshConfig = {
      hosts = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };
  options.nazarewk.programs.gnupg.forwarding.server = {
    enable = mkEnableOption "GnuPG forwarding from remote systems";
    socketPath =  mkOption {
      default = "${cfg.socketPath}.remote";
    };
    user = mkOption {
      default = "nazarewk";
    };
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      nazarewk.programs.gnupg.enable = true;

      home-manager.users.${client.user} = {
        programs.ssh.extraConfig = ''
          Host ${client.sshConfig.hosts}
            RemoteForward /home/${server.user}/${server.socketPath} /home/${client.user}/${client.socketPath}
            ExitOnForwardFailure yes
        '';
        home.file.".gnupg/gpg-agent.conf".text = ''
          keep-display
          extra-socket ~/${cfg.socketPath}
        '';
      };

    })
    (mkIf cfg.server.enable {
      nazarewk.programs.gnupg.enable = true;
      services.openssh.extraConfig = ''
      StreamLocalBindUnlink yes
      '';
    })
  ];
}