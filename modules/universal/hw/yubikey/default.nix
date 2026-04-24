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
                yubioath-flutter
              ]
            );
        }
        (lib.mkIf config.kdn.security.secrets.allowed {
          # SOPS+age config
          kdn.security.secrets.age.plugins = with pkgs; [ age-plugin-yubikey ];
          kdn.env.packages = with pkgs; [ age-plugin-yubikey ];
          kdn.programs.gnupg.enable = true;
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
            (lib.mkIf config.kdn.security.secrets.allowed {
              # SOPS+age config
              services.pcscd.enable = true;
              systemd.services.sops-install-secrets.after = [ "pcscd.socket" ];
              systemd.services.sops-install-secrets.requires = [ "pcscd.socket" ];
            })
          ]
        ))
      ]
    ))
  ];
}
