{ config, pkgs, lib, ... }:
{
  imports = [
    ../../users/nazarewk
  ];

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
  };

  nazarewk.headless.base.enable = true;

  services.locate.enable = true;
  services.locate.localuser = null;
  services.locate.locate = pkgs.mlocate;
  services.locate.pruneBindMounts = true;
}