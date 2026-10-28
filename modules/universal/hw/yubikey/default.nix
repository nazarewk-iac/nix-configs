{
  lib,
  pkgs,
  config,
  kdnConfig,
  ...
}:
let
  cfg = config.kdn.hw.yubikey;
in
{
  # TODO: run gpg-smartcard-reset-keys for users when plugging in/changing yubikeys?
  options.kdn.hw.yubikey = {
    enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
    appId = lib.mkOption {
      type = lib.types.str;
      default = "pam://${config.kdn.hostName}";
    };
    devices = lib.mkOption {
      # TODO: kdn-specific
      default = import ./yubikeys.nix;
    };
    requiredForBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether a smart card must answer before `sops-install-secrets` runs.

        `true` (the default) keeps `sops-install-secrets` ordered `after`/`requires` `pcscd.socket`,
        so an unattended decrypt can use a YubiKey. That edge is why this module carries the
        `pcscd` ordering workaround below: a default `pcscd.socket` is `After=sysinit.target` while
        sops-nix runs `Before=sysinit.target`, so the pair closes a cycle that systemd breaks by
        deleting the sops job. The host then decrypts nothing and, because `sshd` requires the
        secrets target, refuses port 22 on every interface.

        Set `false` on a host with another unattended identity, for example a TPM
        (`kdn.security.secrets.age.tpm.enable` in the den tree). The module then drops the
        `pcscd` edge, and with it the cycle and the workaround, from that host's boot path. The
        YubiKey recipients stay valid for a manual decrypt.
      '';
    };
  };

  config = lib.mkMerge [
    (kdnConfig.util.ifHMParent {
      home-manager.sharedModules = [ { kdn.hw.yubikey = lib.mkDefault cfg; } ];
    })
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          # General YubiKey configs
          kdn.env.packages =
            with pkgs;
            [
              xkcdpass
              yubikey-manager
              yubikey-personalization
              yubico-pam
            ]
            ++ lib.optionals config.kdn.desktop.enable (
              with pkgs;
              [
                (lib.mkIf (!stdenv.hostPlatform.isDarwin) yubioath-flutter)
              ]
            );
        }
        (lib.mkIf config.kdn.security.secrets.allowed {
          # SOPS+age config
          kdn.security.secrets.age.plugins = with pkgs; [ age-plugin-yubikey ];
          kdn.env.packages = with pkgs; [ age-plugin-yubikey ];
          kdn.programs.gnupg.enable = lib.mkDefault true;
          kdn.security.secrets.age.genScripts = [
            (pkgs.writeShellApplication {
              name = "kdn-sops-age-gen-keys-yubikey";
              runtimeInputs = with pkgs; [
                gnugrep
                age-plugin-yubikey
              ];
              runtimeEnv.ALLOW_ROOT_DEFAULT = "false";
              text = ''
                #: "''${ALLOW_ROOT:="$ALLOW_ROOT_DEFAULT"}"
                #if test "$ALLOW_ROOT" == false && test "$EUID" == 0 ; then
                #  echo "should not discover YubiKeys as root" >&2
                #  exit 0
                #fi
                age-plugin-yubikey --identity | grep '^AGE-PLUGIN-YUBIKEY-' || :
              '';
            })
          ];
        })
        (kdnConfig.util.ifHM {
          programs.gpg.scdaemonSettings = {
            # disable-ccid to make YubiKey work
            # - https://support.yubico.com/hc/en-us/articles/360013714479-Troubleshooting-Issues-with-GPG
            # - https://dev.gnupg.org/T5451
            disable-ccid = true;
            pcsc-shared = true;

            # PIN caching fix
            # - https://github.com/drduh/YubiKey-Guide/issues/135
            # - https://dev.gnupg.org/T3362
            # fix from https://dev.gnupg.org/T5436#148656
            disable-application = "piv";
          };
        })
        (kdnConfig.util.ifTypes [ "darwin" ] (
          lib.mkMerge [
            {
              programs.gnupg.agent.enable = true;
            }
          ]
        ))
        (kdnConfig.util.ifTypes [ "nixos" ] (
          lib.mkMerge [
            {
              # U2F config
              services.udev.packages = with pkgs; [
                yubikey-personalization
                libfido2 # pulls in https://github.com/Yubico/libfido2/blob/main/udev/70-u2f.rules
              ];
              users.groups.plugdev = { };
              security.pam.u2f.enable = true;
              security.pam.u2f.settings = {
                enable = true;
                cue = true;
                appid = cfg.appId;
                origin = cfg.appId;
              };
            }
            (lib.mkIf (config.kdn.security.secrets.allowed && cfg.requiredForBoot) {
              # SOPS+age config
              services.pcscd.enable = true;

              # Break the `sysinit.target` ordering cycle that the `sops-install-secrets` edge below
              # creates. sops-nix runs `sops-install-secrets.service` `Before=sysinit.target` and
              # `WantedBy=sysinit.target`. This module then adds `After=pcscd.socket` +
              # `Requires=pcscd.socket` to it. A default `pcscd.socket` carries
              # `DefaultDependencies=yes`, which makes it `After=sysinit.target`; so the cycle is
              #   sysinit.target -> sops-install-secrets -> pcscd.socket -> sysinit.target.
              # systemd breaks it by deleting the `sops-install-secrets.service/start` job, so no
              # secret is ever decrypted, `kdn-secrets.target` never fires, and `sshd` (which
              # `Requires` that target) never starts — the host then refuses port 22 on every
              # interface.
              #
              # Dropping the default dependencies makes `pcscd` order after `local-fs.target` alone,
              # so its own ordering cannot route back through `sysinit.target`.
              # `networking/router/default.nix` writes the same fix for the same cycle on routers.
              systemd.services.pcscd.unitConfig.DefaultDependencies = false;
              systemd.services.pcscd.after = [ "local-fs.target" ];
              systemd.sockets.pcscd.unitConfig.DefaultDependencies = false;
              systemd.sockets.pcscd.after = [ "local-fs.target" ];

              systemd.services.sops-install-secrets.after = [ "pcscd.socket" ];
              systemd.services.sops-install-secrets.requires = [ "pcscd.socket" ];
            })
          ]
        ))
      ]
    ))
  ];
}
