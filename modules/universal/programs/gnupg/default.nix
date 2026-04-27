{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.programs.gnupg;

  fallbackPinentry =
    with pkgs.stdenv.hostPlatform;
    if isDarwin then pkgs.pinentry_mac else pkgs.pinentry-all;
in
{
  options.kdn.programs.gnupg = {
    enable = lib.mkEnableOption "GnuPG forwarding to remote systems";
    pinentry = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kdn.pinentry;
    };
    pass-secret-service.enable = lib.mkEnableOption "pass-secret-service";
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.programs.gnupg = lib.mkDefault cfg; } ];
    })
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          kdn.env.packages = with pkgs; [
            (lib.hiPrio cfg.pinentry)
            (lib.lowPrio fallbackPinentry)

            opensc
            pcsc-tools

            (pkgs.writeShellApplication {
              name = "pass-pubkeys";
              runtimeInputs = with pkgs; [
                pass
                gnupg
                gawk
              ];
              text = builtins.readFile ./pass-pubkeys.sh;
            })

            pkgs.kdn.gpg-smartcard-reset-keys
          ];
        }
        (kdnConfig.util.ifHM {
          programs.password-store.enable = true;
          programs.password-store.settings = {
            PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
            PASSWORD_STORE_CLIP_TIME = "10";
            # for Android interoperability, see https://github.com/drduh/YubiKey-Guide/issues/152#issuecomment-852176877
            PASSWORD_STORE_GPG_OPTS = "--no-throw-keyids";
          };
          programs.gpg.settings.no-throw-keyids = true;
          programs.gpg.enable = true;
          kdn.disks.persist."usr/data".directories = [
            {
              directory = ".gnupg";
              mode = "0700";
            }
          ];
          kdn.disks.persist."usr/config".directories = [
            ".config/pinentry-kdn"
          ];
          #systemd.user.tmpfiles.settings.kdn-gnupg.rules."%h/.config/pinentry-kdn".d.mode="0700";
          systemd.user.tmpfiles.rules = [
            "d %h/.config/pinentry-kdn 0700 - - -"
          ];
        })
        (kdnConfig.util.ifTypes [ "nixos" "darwin" ] {
          programs.gnupg.agent.enable = true;
          programs.gnupg.agent.enableSSHSupport = false;
        })
        (kdnConfig.util.ifTypes [ "darwin" ] (
          lib.mkMerge [
          ]
        ))
        (kdnConfig.util.ifTypes [ "nixos" ] (
          lib.mkMerge [
            {
              services.pcscd.enable = true;
              hardware.gpgSmartcards.enable = true;
              programs.gnupg.agent.enableBrowserSocket = true;
              programs.gnupg.agent.enableExtraSocket = true;
              # cannot remove keys from the agent and YubiKey GPG is not set up/set up with unknown password
              programs.gnupg.agent.pinentryPackage = cfg.pinentry;

              # allow usb-ip access to Yubikeys
              security.polkit.extraConfig = builtins.readFile ./pcsc-lite-rules.js;
            }
            (lib.mkIf cfg.pass-secret-service.enable (
              lib.mkMerge [
                {
                  services.passSecretService.enable = true;
                  services.passSecretService.package = pkgs.kdn.pass-secret-service;
                  systemd.user.services."dbus-org.freedesktop.secrets" = {
                    aliases = [ "pass-secret-service.service" ];
                    after = [ "graphical-session-pre.target" ];
                    partOf = [ "graphical-session.target" ];
                    serviceConfig = {
                      Restart = "on-failure";
                      RestartSec = 1;
                      ExecStartPost = "${pkgs.coreutils}/bin/sleep 2";
                    };
                  };

                  services.gnome.gnome-keyring.enable = lib.mkForce false;
                  home-manager.sharedModules = [ { services.gnome-keyring.enable = lib.mkForce false; } ];
                }
                (lib.mkIf config.kdn.desktop.sway.enable {
                  systemd.user.services."dbus-org.freedesktop.secrets" = {
                    requires = [ config.kdn.desktop.sway.systemd.envs.target ];
                    after = [ config.kdn.desktop.sway.systemd.envs.target ];
                  };
                })
              ]
            ))
            {
              systemd.user.services."gpg-agent" = {
                after = [
                  #"preservation.target" # TODO: no such unit
                ];
                serviceConfig.Slice = "background.slice";
                # TODO: run it when re-plugging smartcards/yubikeys
                postStart = ''
                  if ! ${lib.getExe pkgs.kdn.gpg-smartcard-reset-keys} ; then
                    echo 'WARNING: gpg-smartcard-reset-keys failed!'
                  fi
                '';
              };
            }
          ]
        ))
      ]
    ))
  ];
}
