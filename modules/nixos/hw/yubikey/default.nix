{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.kdn.hw.yubikey;
in {
  # TODO: run gpg-smartcard-reset-keys for users when plugging in/changing yubikeys?
  options.kdn.hw.yubikey = {
    enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
    appId = lib.mkOption {
      type = lib.types.str;
      default = "pam://${config.kdn.hostName}";
    };
    devices = lib.mkOption {};
  };

  imports = [./yubikeys.nix];

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # General YubiKey configs
      services.udev.packages = with pkgs; [yubikey-personalization];
      environment.systemPackages = with pkgs;
        [xkcdpass yubikey-manager yubikey-personalization yubico-pam]
        ++ lib.optionals config.kdn.desktop.enable (with pkgs; [
          yubioath-flutter
        ]);
    }
    {
      # GNUPG configs
      kdn.programs.gnupg.enable = true;
      services.pcscd.enable = true;

      home-manager.sharedModules = [
        {
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

          # for Android interoperability, see https://github.com/drduh/YubiKey-Guide/issues/152#issuecomment-852176877
          programs.password-store.settings.PASSWORD_STORE_GPG_OPTS = "--no-throw-keyids";
          programs.gpg.settings.no-throw-keyids = true;
        }
      ];
    }
    {
      # U2F config
      services.udev.packages = with pkgs; [
        libfido2 # pulls in https://github.com/Yubico/libfido2/blob/main/udev/70-u2f.rules
      ];
      users.groups.plugdev = {};
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
      sops.age.plugins = with pkgs; [age-plugin-yubikey];
      environment.systemPackages = with pkgs; [age-plugin-yubikey];
      systemd.services.sops-install-secrets.after = ["pcscd.socket"];
      systemd.services.sops-install-secrets.requires = ["pcscd.socket"];
      kdn.security.secrets.age.genScripts = [
        (pkgs.writeShellApplication {
          name = "kdn-sops-age-gen-keys-yubikey";
          runtimeInputs = with pkgs; [gnugrep age-plugin-yubikey];
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
  ]);
}
