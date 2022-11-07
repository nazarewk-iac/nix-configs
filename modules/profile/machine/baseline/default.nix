{ lib, pkgs, config, ... }:
let
  cfg = config.kdn.profile.machine.baseline;
in
{
  options.kdn.profile.machine.baseline = {
    enable = lib.mkEnableOption "enable baseline machine profile";
  };

  imports = [
    ../../../../machines/wireguard-peers.nix
  ];

  config = lib.mkIf cfg.enable {
    kdn.enable = true;
    kdn.profile.user.me.enable = true;

    # (modulesPath + "/installer/scan/not-detected.nix")
    hardware.enableRedistributableFirmware = true;

    networking.nameservers = [
      "2606:4700:4700::1111" # CloudFlare
      "1.1.1.1" # CloudFlare
      "8.8.8.8" # Google
    ];
    networking.networkmanager.enable = true;

    # REMOTE access
    services.openssh.enable = true;
    services.openssh.openFirewall = true;
    services.openssh.passwordAuthentication = false;
    kdn.programs.gnupg.enable = true;
    kdn.programs.gnupg.pass-secret-service.enable = true;

    # LOCALE
    i18n.defaultLocale = "en_US.UTF-8";
    i18n.extraLocaleSettings = {
      LC_TIME = "en_GB.UTF-8"; # en_GB - Monday as first day of week
    };
    time.timeZone = "Europe/Warsaw";
    location.provider = "geoclue2";

    # USERS
    users.users.root.initialHashedPassword = "";

    services.avahi.enable = true;

    environment.systemPackages = with pkgs; [
      cachix
    ];

    environment.shellAliases = {
      "userctl" = "systemctl --user";
      "userjournal" = "journalctl --user";
      "sc" = "systemctl";
      "sj" = "journalctl";
      "uc" = "userctl";
      "uj" = "userjournal";
      "scs" = "sc status";
      "ucs" = "uc status";
    };

    kdn.headless.base.enable = true;

    services.locate.enable = true;
    services.locate.localuser = null;
    services.locate.locate = pkgs.mlocate;
    services.locate.pruneBindMounts = true;

    kdn.networking.wireguard.enable = true;
    kdn.hardware.usbip.enable = true;
    kdn.hardware.qmk.enable = true;
    kdn.development.shell.enable = true;
  };
}
