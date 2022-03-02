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
  };

  options.nazarewk.programs.gnupg.forwarding.client = {
    enable = mkEnableOption "GnuPG forwarding to remote systems";
    user = mkOption {
      default = server.user;
    };
    uid = mkOption {
      default = config.users.users.${client.user}.uid;
    };
    socketPath =  mkOption {
      default = "/run/user/${toString client.uid}/gnupg/S.gpg-agent.extra";
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
      default = "/run/user/${toString server.uid}/gnupg/S.gpg-agent";
    };
    user = mkOption {
      type = types.str;
    };
    uid = mkOption {
      default = config.users.users.${server.user}.uid;
    };
  };

  config = mkMerge [
    (mkIf cfg.client.enable {
      nazarewk.programs.gnupg.enable = true;
      programs.gnupg.agent.enableExtraSocket = true;

      home-manager.users.${client.user} = {
        programs.ssh.extraConfig = ''
          Host ${builtins.concatStringsSep " " client.sshConfig.hosts}
            RemoteForward ${server.socketPath} ${client.socketPath}
            ExitOnForwardFailure yes
        '';
        home.file.".gnupg/gpg-agent.conf".text = ''
          # keep-display
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