{ lib, pkgs, config, inputs, system, ... }:
with lib;
let
  cfg = config.kdn.hardware.yubikey;
in
{
  options.kdn.hardware.yubikey = {
    enable = lib.mkEnableOption "YubiKey + GnuPG Smart Card config";
  };

  config = mkIf cfg.enable {
    kdn.programs.gnupg.enable = true;

    home-manager.sharedModules = [
      {
        home.file.".gnupg/scdaemon.conf".text = ''
          pcsc-shared
          # disable-ccid to make YubiKey work
          # - https://support.yubico.com/hc/en-us/articles/360013714479-Troubleshooting-Issues-with-GPG
          # - https://dev.gnupg.org/T5451
          disable-ccid

          # PIN caching fix
          # - https://github.com/drduh/YubiKey-Guide/issues/135
          # - https://dev.gnupg.org/T3362
          # fix from https://dev.gnupg.org/T5436#148656
          disable-application piv
        '';
        home.file.".gnupg/gpg-agent.conf".text = ''
        '';
      }
    ];

    # YubiKey
    # https://nixos.wiki/wiki/Yubikey
    services.udev.packages = [
      pkgs.yubikey-personalization
      pkgs.libfido2 # pulls in https://github.com/Yubico/libfido2/blob/main/udev/70-u2f.rules
    ];

    users.groups.plugdev = { };
    security.pam.u2f = {
      enable = true;
      cue = true;
    };

    environment.systemPackages = with pkgs; [
      xkcdpass
      yubioath-desktop
      yubikey-manager
      yubikey-manager-qt
      yubikey-personalization
      yubikey-personalization-gui
      yubico-pam
    ];

    # see https://dev.gnupg.org/T6179
    # stick to 2.3.6 due to errors in 2.3.7:
    # Aug 31 11:45:58 gpg-agent[40089]: scdaemon[40089]: detected reader 'Yubico YubiKey OTP+FIDO+CCID 00 00'
    # Aug 31 11:45:58 gpg-agent[40089]: scdaemon[40089]: DBG: Curve with OID not supported:  2b06010401da470f01
    # Aug 31 11:45:58 gpg-agent[40089]: scdaemon[40089]: no supported card application found: Card error
    programs.gnupg.package = inputs.nixpkgs-gpg236.legacyPackages.${system}.gnupg;
  };
}
