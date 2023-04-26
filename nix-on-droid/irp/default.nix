{ config, lib, pkgs, ... }:

{
  # Simply install just the packages
  environment.packages = with pkgs; [
    vim
    bzip2
    coreutils
    diffutils
    direnv
    findutils
    git
    gnugrep
    gnupg
    gnused
    gnutar
    gzip
    hostname
    jq
    man
    nix
    openssh
    rsync
    tzdata
    unzip
    utillinux
    xz
    zip

    atuin
    fish
  ];

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "22.11";

  # Set up nix for flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Set your time zone
  time.timeZone = "Europe/Warsaw";

  user.shell = "${pkgs.fish}/bin/fish";

  # Configure home-manager
  home-manager = {
    config = ./hm.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };
}
