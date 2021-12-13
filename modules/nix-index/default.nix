{ pkgs, nixpkgs, ... }: {
    environment.interactiveShellInit = ''
      source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
    '';
    # use nix-index without `nix-channel`
    # see https://github.com/bennofs/nix-index/issues/167
    nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
    environment.systemPackages = with pkgs; [ nix-index ];
}