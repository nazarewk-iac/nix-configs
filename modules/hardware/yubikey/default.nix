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
    # yubioath-desktop
    # yubikey-manager
    # yubikey-manager-qt
    yubikey-personalization
    yubikey-personalization-gui
    yubico-pam

    pinentry-qt
    pinentry-curses
    pinentry-gnome
  ];

  nixpkgs.overlays = [
    # doesn't work
#    (self: super: {
#       yubikey-manager = super.yubikey-manager.overrideAttrs (old: {
#         src = super.fetchFromGitHub {
#           repo = "yubikey-manager";
#           # https://github.com/Yubico/yubikey-manager/tree/32914673d1d0004aba820e614ac9a9a640b4d196
#           rev = "32914673d1d0004aba820e614ac9a9a640b4d196";
#           owner = "Yubico";
#           sha256 = "sha256-hplTi9H1hncEGeyaogUYMzmTVfqZhc7ygz2jsCy/l34=";
#         };
#       });
#    })
  ];
}