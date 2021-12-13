{ pkgs, ... }: {
  programs.gnupg.agent.enable = true;
  programs.gnupg.agent.pinentryFlavor = "qt";

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