{ pkgs, ... }:
{
  environment.etcBackupExtension = ".bak";
  system.stateVersion = "22.11";
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';
  time.timeZone = "Europe/Warsaw";
  user.shell = "${pkgs.fish}/bin/fish";

  environment.etc."ssh/sshd_config".text = "";

  # Configure home-manager
  home-manager = {
    config = ./hm.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
