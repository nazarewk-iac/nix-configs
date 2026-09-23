# The zellij terminal multiplexer, as a universal module.
#
# It installs zellij, writes the Home Manager configuration, and — when `web.enable` is on —
# runs the built-in web interface behind HTTPS. The web server is a systemd user service on
# Linux. It binds loopback by default; set `web.bindAddress = "0.0.0.0"` and name the
# interfaces in `web.firewallInterfaces` to expose it.
{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.zellij;

  # The key the user service reads. A host that sets `keySopsFile` gets the decrypted copy;
  # a host that sets `keyFile` names its own path.
  webKeyPath =
    if cfg.web.keyFile != null then
      cfg.web.keyFile
    else
      "/run/secrets/kdn/zellij/${config.kdn.hostName}.key";
in
{
  options.kdn.programs.zellij = {
    enable = lib.mkEnableOption "the zellij terminal multiplexer";

    web = {
      enable = lib.mkEnableOption "the zellij web interface";

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = ''
          Address the web server binds. The default keeps it on loopback. Set `0.0.0.0` to
          expose it, and open the port with `firewallInterfaces`.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "TCP port of the web server.";
      };

      certFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "PEM certificate the web server serves. Required off loopback.";
      };

      keyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          PEM private key of `certFile`. It must be readable by the user that runs the web
          server. When `keySopsFile` is set and this is null, the module decrypts the key to a
          user-readable path and uses that path.
        '';
      };

      keySopsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          SOPS-encrypted (raw/binary) private key. A system service decrypts it into
          `/run/secrets/kdn/zellij/<hostName>.key`, owned by `user`, mode 0400. Set `user`.
        '';
      };

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OS user that runs the web server and owns the decrypted key.";
      };

      firewallInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "nb-priv" ];
        description = "Interfaces whose firewall opens `port`.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (kdnConfig.util.ifHMParent {
        home-manager.sharedModules = [
          { kdn.programs.zellij = kdnConfig.util.modules.forwardAttrsAsDefaults cfg; }
        ];
      })
      (kdnConfig.util.ifHM (
        lib.mkMerge [
          {
            programs.zellij.enable = true;
            programs.zellij.enableBashIntegration = true;
            # fish has its own auto-attach-to-`main` logic below instead of the generic
            # home-manager auto-start snippet: enabling both stacks two zellij-launchers in
            # sequence, so quitting/detaching from `main` falls through into the second one
            # spawning a brand new unnamed session.
            programs.zellij.enableFishIntegration = false;
            programs.zellij.enableZshIntegration = true;
            programs.zellij.attachExistingSession = false; # don't attach to just any session
            # auto-attach to `main` session, but never over SSH: SSH sessions should land in a
            # plain shell unless zellij is invoked explicitly.
            #
            # Attach only when `main` has no client attached on THIS machine. This stops zellij
            # from opening in every terminal window: the first window attaches, the next windows
            # get a plain shell. `zellij action list-clients` sees only clients on the local
            # zellij server (one server per machine), so a `main` open on a remote host over SSH
            # is a separate server and does not count here.
            programs.fish.interactiveShellInit = ''
              if status is-interactive; and not set -q ZELLIJ; and not set -q SSH_CONNECTION; and not set -q SSH_TTY
                set -l kdn_zellij_clients (zellij --session main action list-clients 2>/dev/null)
                if string match --quiet 'CLIENT_ID*' -- $kdn_zellij_clients[1]; and test (count $kdn_zellij_clients) -gt 1
                  # `main` is attached in another window on this machine; land in a plain shell.
                else
                  zellij attach --create main
                end
              end
            '';
            kdn.disks.persist."usr/cache".directories = [ ".cache/zellij" ];
            # The web server keeps its login tokens here.
            kdn.disks.persist."usr/data".directories = [ ".local/share/zellij" ];
            programs.zellij.settings.scroll_buffer_size = 1 * 1000 * 1000;
            # TODO: this is "temporary" measure to use built-in theme instead of stylix
            programs.zellij.settings.theme = "dracula";
            # fix Delete working as Ctrl + H on external keyboard
            programs.zellij.settings.support_kitty_keyboard_protocol = true;
          }
          (lib.mkIf (cfg.web.enable && pkgs.stdenv.hostPlatform.isLinux) {
            systemd.user.services.zellij-web = {
              Unit = {
                Description = "Zellij web interface";
                After = [ "network.target" ];
              };
              Service = {
                Type = "simple";
                ExecStart = lib.escapeShellArgs [
                  (lib.getExe config.programs.zellij.finalPackage)
                  "web"
                  "--start"
                  "--ip"
                  cfg.web.bindAddress
                  "--port"
                  (toString cfg.web.port)
                  "--cert"
                  cfg.web.certFile
                  "--key"
                  webKeyPath
                ];
                # The key may not exist yet at first start; retry.
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "default.target" ];
            };
          })
        ]
      ))
      (kdnConfig.util.ifTypes [ "nixos" ] (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion =
                  !cfg.web.enable
                  || (cfg.web.certFile != null && (cfg.web.keyFile != null || cfg.web.keySopsFile != null));
                message = "kdn.programs.zellij.web: `certFile` and one of `keyFile`/`keySopsFile` are required when the web interface is on";
              }
              {
                assertion = !(cfg.web.enable && cfg.web.keySopsFile != null) || cfg.web.user != null;
                message = "kdn.programs.zellij.web: `user` is required when `keySopsFile` is set";
              }
            ];
          }
          (lib.mkIf (cfg.web.enable && cfg.web.firewallInterfaces != [ ]) {
            networking.firewall.interfaces = lib.genAttrs cfg.web.firewallInterfaces (_: {
              allowedTCPPorts = [ cfg.web.port ];
            });
          })
          (lib.mkIf (cfg.web.enable && cfg.web.keySopsFile != null) {
            systemd.services.kdn-zellij-web-key = {
              description = "Decrypt the zellij web TLS private key into /run/secrets";
              wantedBy = [ "multi-user.target" ];
              path = [
                pkgs.sops
                pkgs.coreutils
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = "root";
                Group = "root";
              };
              script = ''
                set -euo pipefail
                mkdir -p /run/secrets/kdn/zellij
                ${pkgs.sops}/bin/sops decrypt --output-type binary \
                  ${cfg.web.keySopsFile} > /run/secrets/kdn/zellij/${config.kdn.hostName}.key
                chown ${cfg.web.user} /run/secrets/kdn/zellij/${config.kdn.hostName}.key
                chmod 0400 /run/secrets/kdn/zellij/${config.kdn.hostName}.key
              '';
            };
          })
        ]
      ))
    ]
  );
}
