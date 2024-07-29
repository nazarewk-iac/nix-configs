{ lib, pkgs, config, inputs, system, ... }:
let
  cfg = config.kdn.hardware.yubikey;
in
{
  options.kdn.hardware.yubikey = {
    enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
    appId = lib.mkOption {
      type = lib.types.str;
      default = "pam://${config.networking.hostName}";
    };
    devices = lib.mkOption { };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      kdn.hardware.yubikey.devices.laptop = {
        enabled = true;
        serial = "16174038";
        notes = [ "data in KeePass" ];
      };
      # age-plugin-yubikey Slot 1 is PIV Slot 82
      kdn.hardware.yubikey.devices.laptop.piv."82" = {
        type = "age-plugin-yubikey";
        age-plugin-yubikey = {
          name = "age identity 97b9264f";
          pin-policy = "always";
          touch-policy = "cached";
          notes = [ "sops" ];
          recipient = "age1yubikey1q05un9a8q2x783srmhv4hm3pjsrxvgrw92q70yyzjmlx3wnd8jwn2x8ghlp";
          identity = "AGE-PLUGIN-YUBIKEY-16M9LVQYZJ7UJVNC8Z7TW7";
        };
      };
      kdn.hardware.yubikey.devices.desktop = {
        enabled = true;
        serial = "1617439";
        notes = [ "data in KeePass" ];
      };
      kdn.hardware.yubikey.devices.desktop.piv."82" = {
        type = "age-plugin-yubikey";
        age-plugin-yubikey = {
          notes = [ "sops" ];
          name = "age identity cd6e23c9";
          pin-policy = "always";
          touch-policy = "cached";
          recipient = "age1yubikey1qdppx4kd82ecfxr5lcmgef9w4zxmreyl2q3xv6dsq2jwgv274cm5zmjuy34";
          identity = "AGE-PLUGIN-YUBIKEY-16L9LVQYZE4HZ8JGY5HK5P";
        };
      };
    }
    {
      # General YubiKey configs
      services.udev.packages = with pkgs;[
        yubikey-personalization
      ];
      environment.systemPackages = with pkgs; [
        xkcdpass
        yubikey-manager
        #yubikey-manager-qt # TODO: 2023-03-03 failed to build with ERROR: Could not find a version that satisfies the requirement cryptography<39,>=2.1
        yubikey-personalization
        yubikey-personalization-gui
        yubico-pam
      ];
    }
    {
      # GNUPG configs
      kdn.programs.gnupg.enable = true;
      services.pcscd.enable = true;

      home-manager.sharedModules = [{
        programs.gpg.enable = true;
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
      }];
    }
    {
      # U2F config
      services.udev.packages = with pkgs;[
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
    {
      # SOPS+age config
      services.pcscd.enable = true;
      environment.systemPackages = with pkgs; [
        (pkgs.callPackage ./sops.nix { })
        age
        rage
        age-plugin-yubikey
        age-plugin-fido2-hmac
      ];
      home-manager.sharedModules = [{
        xdg.configFile."sops/age/keys.txt".text = lib.pipe cfg.devices [
          (lib.attrsets.mapAttrsToList (_: yk: lib.attrsets.mapAttrsToList
            (slotNum: slot:
              lib.optional (slot.type == "age-plugin-yubikey") (with slot."${slot.type}"; ''
                #      Yubikey: ${yk.serial}
                #     PIV Slot: ${slotNum}
                #  Plugin Slot: ${builtins.toString (lib.strings.toInt slotNum - 82)}
                #    Recipient: ${recipient}
                ${identity}
              ''))
            yk.piv))
          lib.flatten
          (builtins.concatStringsSep "\n")
        ];
      }];
    }
  ]);
}
