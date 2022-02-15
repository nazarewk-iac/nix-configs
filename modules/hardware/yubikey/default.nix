{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.nazarewk.hardware.yubikey;
in {
  options.nazarewk.hardware.yubikey = {
    enable = mkEnableOption "YubiKey + GnuPG Smart Card config";
  };

  config = mkIf cfg.enable {
    programs.gnupg.agent.enable = true;
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

    security.pam.yubico = {
      enable = true;
      # debug = true;
      mode = "challenge-response";
    };

    services.pcscd.enable = true;

    environment.systemPackages = with pkgs; [
      yubioath-desktop
      yubikey-manager
      yubikey-manager-qt
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
  };
}