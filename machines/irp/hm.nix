{ config, lib, pkgs, ... }:
let
  ssh = import ../../modules/profile/user/me/ssh.nix { inherit lib; };
in
{
  # Read the changelog before changing this value
  home.stateVersion = "23.11";

  # insert home-manager config
  home.file.".ssh/authorized_keys".text = ssh.authorizedKeysText;
  home.packages = with pkgs; [
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
    procps
    rsync
    tzdata
    unzip
    utillinux
    vim
    xz
    zip

    atuin
    fish

    (pkgs.writeShellApplication {
      name = "irp-switch";
      runtimeInputs = with pkgs; [ ];
      text = ''
        nix-on-droid "''${1:-switch}" --flake "$HOME/dev/github.com/nazarewk-iac/nix-configs" "''${@:2}"
      '';
    })

    (pkgs.writeShellApplication {
      name = "irp-update";
      runtimeInputs = with pkgs; [ git ];
      text = ''
        cd "$HOME/dev/github.com/nazarewk-iac/nix-configs"
        git pull
        irp-switch "$@"
      '';
    })

    (pkgs.writeShellApplication {
      name = "start-sshd";
      runtimeInputs = with pkgs; [ openssh ];
      text = ''
      '';
    })
  ];
}
