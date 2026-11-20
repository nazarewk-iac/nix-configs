# The zellij terminal multiplexer, as a universal module.
#
# It installs zellij, writes the Home Manager configuration, and — when `web.enable` is on —
# runs the built-in web interface behind HTTPS. The web server is a systemd user service on
# Linux. It binds loopback by default; set `web.bindAddress = "0.0.0.0"` and name the
# interfaces in `web.firewallInterfaces` to expose it.
#
# Two web settings shape what a client sees: `web.sharedByDefault` marks new sessions as shared
# (`web_sharing`), so the phone can attach without the Share plugin; `web.mobileFontSize` sets
# `web_client.mobile_font_size`, the mobile-only font size (the built-in 24px reads as a ~3x
# zoom on a high-DPI phone). Both come from the nazarewk-iac zellij fork.
{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.zellij;
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
          server.
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

      sharedByDefault = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Start every session shared with the web client (`web_sharing "on"`). A session reads
          this value when it starts, so a session that is already running keeps its old value.
          The web server still needs a login token, and a token can be read-only.
        '';
      };

      mobileFontSize = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 96);
        default = 10;
        example = 12;
        description = ''
          Font size in pixels for mobile viewports only (`web_client.mobile_font_size`, from the
          nazarewk-iac zellij fork). Desktop web clients keep `web_client.font_size`. The built-in
          mobile default is 24px, which on a high-DPI phone reads as a ~3x zoom: about 27 columns
          on a 390px-wide screen. `null` keeps the built-in default.

          A stock zellij ignores the key in silence, so a fork overlay that stops applying shows
          the 24px default and no error.
        '';
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
            # Both settings travel in `~/.config/zellij/config.kdl`. `web_sharing` is read by the
            # session when it starts; `web_client.mobile_font_size` is read by the web server.
            programs.zellij.settings = {
              web_sharing = if cfg.web.sharedByDefault then "on" else "off";
            }
            // lib.optionalAttrs (cfg.web.mobileFontSize != null) {
              web_client.mobile_font_size = cfg.web.mobileFontSize;
            };

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
                  cfg.web.keyFile
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
                assertion = !cfg.web.enable || (cfg.web.certFile != null && cfg.web.keyFile != null);
                message = "kdn.programs.zellij.web: `certFile` and `keyFile` are required when the web interface is on";
              }
            ];
          }
          (lib.mkIf (cfg.web.enable && cfg.web.firewallInterfaces != [ ]) {
            networking.firewall.interfaces = lib.genAttrs cfg.web.firewallInterfaces (_: {
              allowedTCPPorts = [ cfg.web.port ];
            });
          })
        ]
      ))
    ]
  );
}
