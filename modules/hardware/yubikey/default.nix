{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.yubikey;
in
{
  options.nazarewk.hardware.yubikey = {
    enable = mkEnableOption "YubiKey + GnuPG Smart Card config";
  };

  config = mkIf cfg.enable {
    nazarewk.programs.gnupg.enable = true;
    programs.gnupg.agent.pinentryFlavor = "qt";

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
    services.udev.packages = [ pkgs.yubikey-personalization ];

    # security.pam.yubico = {
    #   enable = true;
    #   # debug = true;
    #   mode = "challenge-response";
    # };

    security.pam.u2f = {
      enable = true;
      cue = true;
    };

    services.pcscd.enable = true;

    environment.systemPackages = with pkgs; [
      xkcdpass
      pinentry-qt
      yubioath-desktop
      yubikey-manager
      yubikey-manager-qt
      yubikey-personalization
      yubikey-personalization-gui
      yubico-pam
    ];
  };
}
