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

  # YubiKey
  # https://nixos.wiki/wiki/Yubikey
  services.udev.packages = [ pkgs.yubikey-personalization ];

  security.pam.yubico = {
    enable = true;
    # debug = true;
    mode = "challenge-response";
  };

  services.pcscd.enable = true;

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