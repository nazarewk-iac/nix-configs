# used in tandem with <repo>/installer-update.sh
{ config, pkgs, ... }:
{
  imports = [ /etc/nixos/configuration.bkp.nix ];

  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowAliases = false;

  services.openssh.enable = true;
  services.openssh.openFirewall = true;
  services.openssh.passwordAuthentication = false;


  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIFngB2F2qfcXVbXkssSWozufmyc0n6akKYA8zgjNFdZ"
  ];

  environment.systemPackages = with pkgs; [
    git
    jq
  ];
}
