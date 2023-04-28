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
  };

  config = lib.mkIf cfg.enable {
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
          no-throw-keyids
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
      inherit (cfg) appId;
      origin = cfg.appId;
    };

    environment.systemPackages = with pkgs; [
      xkcdpass
      yubikey-manager
      #yubikey-manager-qt # TODO: 2023-03-03 failed to build with ERROR: Could not find a version that satisfies the requirement cryptography<39,>=2.1
      yubikey-personalization
      yubikey-personalization-gui
      yubico-pam
    ];
  };
}
