# YubiKey + GnuPG Smart Card config
{ pkgs, ... }: {
  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "qt";

  home-manager.sharedModules = [
    {
      home.file.".gnupg/scdaemon.conf".text = ''
      pcsc-shared
      disable-ccid
      '';
    }
  ];

  environment.systemPackages = with pkgs; [
    yubioath-desktop
    yubikey-personalization
    yubikey-personalization-gui
    yubikey-manager
    yubikey-manager-qt
    yubico-pam

    pinentry-qt
    pinentry-curses
    pinentry-gnome
  ];
}