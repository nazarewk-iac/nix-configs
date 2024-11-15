{ lib, pkgs, config, inputs, system, ... }:
let cfg = config.kdn.hardware.yubikey;
in {
  options.kdn.hardware.yubikey = {
    enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
    appId = lib.mkOption {
      type = lib.types.str;
      default = "pam://${config.networking.hostName}";
    };
    devices = lib.mkOption { };
  };

  imports = [ ./yubikeys.nix ];

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # General YubiKey configs
      services.udev.packages = with pkgs; [ yubikey-personalization ];
      environment.systemPackages = with pkgs;
        [ xkcdpass yubikey-manager yubikey-personalization yubico-pam ]
        ++ lib.optionals config.kdn.headless.enableGUI (with pkgs;
          [
            #yubikey-manager-qt # TODO: 2023-03-03 failed to build with ERROR: Could not find a version that satisfies the requirement cryptography<39,>=2.1
            yubikey-personalization-gui
          ]);
    }
    {
      # GNUPG configs
      kdn.programs.gnupg.enable = true;
      services.pcscd.enable = true;

      home-manager.sharedModules = [{
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
        programs.password-store.settings.PASSWORD_STORE_GPG_OPTS =
          "--no-throw-keyids";
        programs.gpg.settings.no-throw-keyids = true;
      }];
    }
    {
      # U2F config
      services.udev.packages = with pkgs;
        [
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
    (lib.mkIf config.kdn.security.secrets.enable {
      # SOPS+age config
      services.pcscd.enable = true;
      environment.systemPackages = with pkgs; [ age-plugin-yubikey ];
      kdn.security.secrets.age.genScripts = [
        (pkgs.writeShellApplication {
          name = "kdn-sops-age-gen-keys-yubikey";
          runtimeInputs = with pkgs; [ gnugrep age-plugin-yubikey ];
          /* TODO: watch out for yubikey support in upstream sops:
              - https://github.com/Mic92/sops-nix/issues/377
              - https://github.com/getsops/sops/pull/1465
          */
          runtimeEnv.ALLOW_ROOT_DEFAULT = "false";
          text = ''
            : "''${ALLOW_ROOT:="$ALLOW_ROOT_DEFAULT"}"
            if test "$ALLOW_ROOT" == false && test "$EUID" == 0 ; then
              echo "should not discover YubiKeys as root" >&2
              exit 0
            fi
            age-plugin-yubikey --identity | grep '^AGE-PLUGIN-YUBIKEY-' || :
          '';
        })
      ];
      home-manager.sharedModules = [
        {
          /* TODO: remove the need to run below every time yubikey is changed
                age-plugin-yubikey --identity | grep '^AGE-PLUGIN-YUBIKEY-' >~/.config/sops/age/keys.txt
          */
          ## this should not be present from store, because it will try all keys interactively
          ##  possibly generated on the fly?
          #xdg.configFile."sops/age/keys.txt".text = lib.pipe cfg.devices [
          #  (lib.attrsets.mapAttrsToList (_: yk: lib.attrsets.mapAttrsToList
          #    (slotNum: slot:
          #      lib.optional (slot.type == "age-plugin-yubikey") (
          #        let p = slot."${slot.type}"; in ''
          #          #         Type: age-plugin-yubikey
          #          #      Yubikey: ${yk.serial}
          #          #     PIV Slot: ${slotNum}
          #          #  Plugin Slot: ${builtins.toString ((lib.strings.toInt slotNum) - 82 + 1)}
          #          #   PIN Policy: ${p."pin-policy"}
          #          # Touch Policy: ${p."touch-policy"}
          #          #    Recipient: ${p.recipient}
          #          # Notes:
          #          ${lib.pipe p.notes [
          #            (builtins.map (lib.strings.splitString "\n"))
          #            lib.lists.flatten
          #            (builtins.map (note: "#   ${note}"))
          #            (builtins.concatStringsSep "\n")
          #          ]}
          #          ${p.identity}
          #        ''
          #      ))
          #    yk.piv))
          #  lib.lists.flatten
          #  (builtins.concatStringsSep "\n")
          #];
        }
      ];
    })
  ]);
}
